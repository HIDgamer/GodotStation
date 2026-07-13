using Godot;
using GodotStation.Core.World;
using GodotStation.Game.Mobs;
using GodotStation.Game.Mobs.Health;

namespace GodotStation.Game.Interaction;

public enum GrabLevel { None, Passive, Aggressive, Choke, Fireman }

// Grab/pull/fireman-carry state machine, ported from the old prototype
// (its own original code) - the one piece of the old Grab intent
// CombatResolver.ResolveGrab explicitly left as a stub for. Connection
// rebuild vs. the old version:
//  - GridSystem -> WorldGrid/GridCell throughout; the old pixel-based
//    choke/carry offsets (a raw -8px nudge, etc) don't have an equivalent
//    in a grid-cell world - Choke and Fireman both just share the puller's
//    cell now, Passive/Aggressive trail one cell behind via _Process
//    polling rather than a per-step movement-started hook.
//  - Old Inventory.Equip(GrabItem, slot) hand-occupation + PUI grab-sprite
//    frame cycling is dropped - no GrabItem class/DMI grab-icon frames
//    exist yet. A free hand is still required to start a grab (the
//    resource cost), it just isn't visually occupied by a fake item.
//  - IMobSystem -> IMobComponent; ResolveMobByPeerId name/group lookups
//    are gone (Mob references are passed directly); no sync RPCs (server-
//    authoritative only, state changes go out as plain signals - matches
//    every other reclaimed component). ShowChatBubble -> StatusMessage
//    signal, same as HealthSystem/FireSystem.
//  - CQC/FiremanCarry skill checks now read the real SkillComponent
//    instead of a hardcoded 0 (that component didn't exist until this
//    pass either).
//  - The old "pulled target tries to move -> breaks free + self-stuns"
//    struggle mechanic needs intercepting the pulled mob's own movement
//    request path and isn't wired this pass - CheckForGripLoss (puller
//    moves too far away) and StopPull are the ways a grab currently ends.
public partial class PlayerInteractionSystem : Node, IMobComponent
{
    private const float InteractionSpeedPenalty = 0.5f;
    private const int GripLossDistance = 2;
    private const float BaseFiremanCarryTime = 3.0f;

    [Signal] public delegate void StartedPullingEventHandler(Mob target);
    [Signal] public delegate void StoppedPullingEventHandler();
    [Signal] public delegate void GrabLevelChangedEventHandler(int level);
    [Signal] public delegate void StatusMessageEventHandler(string text);

    private Mob? _owner;
    private Inventory? _inventory;
    private SkillComponent? _skill;
    private DoAfterComponent? _doAfter;

    private Mob? _pullingTarget;
    private Mob? _pulledBy;
    private GrabLevel _grabLevel = GrabLevel.None;

    public void Initialize(Mob mob)
    {
        _owner = mob;
        _inventory = mob.GetMobComponent<Inventory>();
        _skill = mob.GetMobComponent<SkillComponent>();
        _doAfter = mob.GetMobComponent<DoAfterComponent>();
    }

    public void Cleanup()
    {
        if (_pullingTarget != null) StopPull();
    }

    public override void _Process(double delta)
    {
        if (!Multiplayer.IsServer() || _owner == null || _pullingTarget == null) return;

        if (!GodotObject.IsInstanceValid(_pullingTarget))
        {
            _pullingTarget = null;
            _grabLevel = GrabLevel.None;
            return;
        }

        if (_grabLevel >= GrabLevel.Choke)
        {
            if (_pullingTarget.GridCell != _owner.GridCell) MoveTargetTo(_owner.GridCell);
        }
        else
        {
            CheckForGripLoss();
            if (_pullingTarget != null) FollowIfNeeded();
        }
    }

    // Entry point from CombatResolver.ResolveGrab: start a new pull, or
    // escalate an existing one on the same target.
    public void HandleGrabIntent(Mob target)
    {
        if (!Multiplayer.IsServer() || _owner == null || target == _owner) return;

        if (_pullingTarget == target)
        {
            ProgressGrab();
        }
        else if (_pullingTarget == null)
        {
            StartPull(target);
        }
    }

    public void StartPull(Mob target)
    {
        if (!Multiplayer.IsServer() || _owner == null || target == _owner || _pullingTarget != null) return;

        var targetInteraction = target.GetMobComponent<PlayerInteractionSystem>();
        if (targetInteraction?._pulledBy != null)
        {
            EmitSignal(SignalName.StatusMessage, $"{target.AtomName} is already being grabbed.");
            return;
        }

        if (_inventory != null && !_inventory.HasFreeHand())
        {
            EmitSignal(SignalName.StatusMessage, "You need a free hand to grab someone.");
            return;
        }

        _pullingTarget = target;
        _grabLevel = GrabLevel.Passive;
        if (targetInteraction != null) targetInteraction._pulledBy = _owner;

        EmitSignal(SignalName.StartedPulling, target);
        EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
        EmitSignal(SignalName.StatusMessage, $"You grab {target.AtomName}.");
        UpdatePullerSpeed();
    }

    public void StopPull()
    {
        if (!Multiplayer.IsServer() || _pullingTarget == null) return;

        if (GodotObject.IsInstanceValid(_pullingTarget))
        {
            var targetInteraction = _pullingTarget.GetMobComponent<PlayerInteractionSystem>();
            if (targetInteraction != null) targetInteraction._pulledBy = null;

            if (_grabLevel == GrabLevel.Fireman)
            {
                _pullingTarget.GetMobComponent<MobStateSystem>()?.SetState(MobState.Standing);
            }
        }

        _pullingTarget = null;
        _grabLevel = GrabLevel.None;
        UpdatePullerSpeed();

        EmitSignal(SignalName.StoppedPulling);
        EmitSignal(SignalName.GrabLevelChanged, (int)GrabLevel.None);
    }

    public void ProgressGrab()
    {
        if (!Multiplayer.IsServer() || _pullingTarget == null) return;

        if (_grabLevel == GrabLevel.Passive)
        {
            _grabLevel = GrabLevel.Aggressive;
            _pullingTarget.GetMobComponent<MobStateSystem>()?.SetState(MobState.Prone);
            EmitSignal(SignalName.StatusMessage, $"You aggressively grab {_pullingTarget.AtomName}!");
        }
        else if (_grabLevel == GrabLevel.Aggressive)
        {
            _grabLevel = GrabLevel.Choke;
            EmitSignal(SignalName.StatusMessage, $"You start choking {_pullingTarget.AtomName}!");
        }
        else
        {
            return;
        }

        EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
        UpdatePullerSpeed();
    }

    // Ramps up over time (CalculateCarryTime) then lifts the target onto
    // the puller's cell as a Fireman carry - triggered by ClickManager
    // (drag-on-grabbed-mob) once that's ported.
    public void StartFiremanCarry()
    {
        if (!Multiplayer.IsServer() || _owner == null || _pullingTarget == null) return;
        if (_grabLevel < GrabLevel.Aggressive)
        {
            _grabLevel = GrabLevel.Aggressive;
            _pullingTarget.GetMobComponent<MobStateSystem>()?.SetState(MobState.Prone);
            EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
            UpdatePullerSpeed();
        }

        var target = _pullingTarget;
        _doAfter?.StartAction(CalculateCarryTime(),
            onComplete: () =>
            {
                if (_pullingTarget != target || !GodotObject.IsInstanceValid(target)) return;

                _grabLevel = GrabLevel.Fireman;
                target.GetMobComponent<MobStateSystem>()?.SetState(MobState.Grabbed);
                MoveTargetTo(_owner.GridCell);

                EmitSignal(SignalName.StatusMessage, $"You lift {target.AtomName} onto your shoulder.");
                EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
                UpdatePullerSpeed();
            },
            onCancel: () => EmitSignal(SignalName.StatusMessage, "You stop carrying."));
    }

    private float CalculateCarryTime()
    {
        var skillLevel = _skill?.GetSkillLevel(SkillType.FiremanCarry) ?? 0;
        return Mathf.Max(1.0f, BaseFiremanCarryTime - skillLevel * 0.3f);
    }

    private void FollowIfNeeded()
    {
        if (_owner == null || _pullingTarget == null) return;

        var worldGrid = GetWorldGrid();
        if (worldGrid == null || worldGrid.IsAdjacent(_owner.GridCell, _pullingTarget.GridCell)) return;

        var delta = _owner.GridCell - _pullingTarget.GridCell;
        var step = new Vector2I(Mathf.Clamp(delta.X, -1, 1), Mathf.Clamp(delta.Y, -1, 1));
        var desired = _pullingTarget.GridCell + step;

        if (desired != _owner.GridCell && !worldGrid.IsDense(desired)) MoveTargetTo(desired);
    }

    private void CheckForGripLoss()
    {
        if (_owner == null || _pullingTarget == null) return;

        var distance = _owner.GridCell - _pullingTarget.GridCell;
        if (Mathf.Abs(distance.X) <= GripLossDistance && Mathf.Abs(distance.Y) <= GripLossDistance) return;

        EmitSignal(SignalName.StatusMessage, $"You lost your grip on {_pullingTarget.AtomName}.");
        StopPull();
    }

    private void MoveTargetTo(Vector2I cell)
    {
        if (_pullingTarget == null) return;

        var movement = _pullingTarget.GetNodeOrNull<MovementController>("MovementController");
        if (movement != null) movement.ForceSetCell(cell);
        else GetWorldGrid()?.MoveOccupant(_pullingTarget, _pullingTarget.GridCell, cell);
    }

    private void UpdatePullerSpeed()
    {
        var movement = _owner?.GetNodeOrNull<MovementController>("MovementController");
        if (movement == null) return;

        movement.InteractionSpeedMultiplier = _pullingTarget != null && _grabLevel >= GrabLevel.Aggressive
            ? InteractionSpeedPenalty
            : 1.0f;
    }

    private WorldGrid? GetWorldGrid() => GetNodeOrNull<WorldGrid>("/root/WorldGrid");

    public bool IsPulling() => _pullingTarget != null;
    public Mob? GetPulling() => _pullingTarget;
    public GrabLevel GetGrabLevel() => _grabLevel;
    public Mob? GetPulledBy() => _pulledBy;
}
