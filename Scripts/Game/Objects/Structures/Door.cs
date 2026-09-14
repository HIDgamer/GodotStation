using Godot;
using GodotStation.Core.Assets;
using GodotStation.Core.Atoms;
using GodotStation.Core.Diagnostics;
using GodotStation.Core.World;
using GodotStation.Game.Objects;

namespace GodotStation.Game.Objects.Structures;

public enum DoorState { Closed, Opening, Open, Closing }

// Base openable/closable structure occupying a single grid cell - the
// "base door class" stage of Phase 3 (see PORT_ROADMAP.md's Doors/airlocks
// entry). Airlock-specific complexity (wire panel, power rails, bolts,
// forced entry, tool interactions) is a deliberately separate follow-up
// stage, matching the roadmap's own two-stage split for this phase; this
// class is the fully generic open/close/density/bump-to-open contract every
// future door variant (airlocks, blast doors, windoors, ...) builds on.
//
// One scene (Scenes/Game/Door.tscn) covers every visual variant via exported
// IconSheetPath, same composition-over-inheritance convention as Item.
public partial class Door : WorldObject, IDenseStructure, IBumpable
{
    [Export] public string IconSheetPath = "res://Icons/obj/structures/doors/Doorele.png";
    [Export] public float TransitionSeconds = 0.5f;
    [Export] public float AutoCloseSeconds = 5f;

    public DoorState State { get; private set; } = DoorState.Closed;

    // IDenseStructure - dense while fully closed or in the act of closing;
    // density flips the instant a close begins, not once the animation
    // finishes, so nothing can dash through a mid-close door.
    public bool IsDense => State is DoorState.Closed or DoorState.Closing;

    private Sprite2D? _visual;
    private RoundLogger? _log;

    public override void _Ready()
    {
        _visual = GetNodeOrNull<Sprite2D>("Visual");
        _log = GetNodeOrNull<RoundLogger>("/root/RoundLogger");

        var cell = new Vector2I(
            Mathf.FloorToInt(Position.X / WorldGrid.DefaultCellSize),
            Mathf.FloorToInt(Position.Y / WorldGrid.DefaultCellSize));
        SetGridCell(cell);
        GetNode<WorldGrid>("/root/WorldGrid").SetStructure(cell, this);

        UpdateVisual();
    }

    // IBumpable - MovementController calls this when a grid step is blocked
    // by this door instead of just refusing the move outright, matching
    // ucfss13's own "walk into an unlocked airlock to open it" behavior.
    // Only ever reachable server-side (MovementController.TryStepGrid is
    // itself only ever ticked from PlayerMob.ServerTick) but still guarded
    // directly, same belt-and-suspenders convention as every Do*/Request*
    // pair elsewhere in this codebase.
    public void OnBumped()
    {
        if (!Multiplayer.IsServer()) return;
        if (State == DoorState.Closed) Open();
    }

    public void Open()
    {
        if (!Multiplayer.IsServer() || State is DoorState.Open or DoorState.Opening) return;

        SetState(DoorState.Opening);
        GetTree().CreateTimer(TransitionSeconds).Timeout += () =>
        {
            SetState(DoorState.Open);
            ScheduleAutoClose();
        };
    }

    public void Close()
    {
        if (!Multiplayer.IsServer() || State is DoorState.Closed or DoorState.Closing) return;

        SetState(DoorState.Closing);
        GetTree().CreateTimer(TransitionSeconds).Timeout += () => SetState(DoorState.Closed);
    }

    // Keeps retrying rather than closing on top of whoever's standing in the
    // doorway - matches ucfss13's own airlock auto-close behavior.
    private void ScheduleAutoClose()
    {
        if (AutoCloseSeconds <= 0f) return;

        GetTree().CreateTimer(AutoCloseSeconds).Timeout += () =>
        {
            if (State != DoorState.Open) return;

            var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
            if (worldGrid.GetOccupants(GridCell).Count > 0)
            {
                ScheduleAutoClose();
                return;
            }

            Close();
        };
    }

    private void SetState(DoorState state)
    {
        State = state;
        UpdateVisual();
        _log?.Log("DOOR", $"{AtomName} at {GridCell} -> {state}");

        if (Multiplayer.HasMultiplayerPeer() && Multiplayer.IsServer())
        {
            Rpc(nameof(SyncState), (int)state);
        }
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false)]
    private void SyncState(int state)
    {
        State = (DoorState)state;
        UpdateVisual();
    }

    private void UpdateVisual()
    {
        if (_visual == null || IconSheetPath == "") return;

        var iconState = State switch
        {
            DoorState.Closed => "door_closed",
            DoorState.Opening => "door_opening",
            DoorState.Open => "door_open",
            DoorState.Closing => "door_closing",
            _ => "door_closed",
        };

        var sheet = DmiSheet.Load(IconSheetPath);
        _visual.Texture = sheet?.GetFrame(iconState);
    }
}
