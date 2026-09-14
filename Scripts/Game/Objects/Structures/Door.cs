using Godot;
using GodotStation.Core.Assets;
using GodotStation.Core.Atoms;
using GodotStation.Core.Diagnostics;
using GodotStation.Core.World;
using GodotStation.Game.Objects;

namespace GodotStation.Game.Objects.Structures;

public enum DoorState { Closed, Opening, Open, Closing }

// Openable/closable structure occupying a single grid cell, covering both
// Phase 3 stages from PORT_ROADMAP.md's Doors/airlocks entry: the base
// open/close/density/bump-to-open contract, plus airlock parity's power
// rails, bolts, welding, and damage/forced-entry (Integrity/ApplyDamage/
// Destroy are inherited straight from Atom - a destroyed door just means
// OnDestroyed forces it permanently open, no separate damage model needed).
// Every future door variant (blast doors, windoors, ...) builds on this.
//
// Deliberately NOT built here: a wire panel, or any tool-interaction trigger
// (weld shut, cut bolts, force with a crowbar) for a player to actually
// invoke these mechanics with. Both need a real click/tool dispatch system,
// which is Phase 4's job, not this one's - the mechanics below are real and
// fully functional, just driven by debug hooks (PlayerMob's
// debug_door_bolt_toggle, and the existing debug_turf_damage now also
// damaging structures) until Phase 4 gives them a real trigger.
//
// One scene (Scenes/Game/Door.tscn) covers every visual variant via exported
// IconSheetPath, same composition-over-inheritance convention as Item.
public partial class Door : WorldObject, IDenseStructure, IBumpable
{
    [Export] public string IconSheetPath = "res://Icons/obj/structures/doors/Doorele.png";
    [Export] public float TransitionSeconds = 0.5f;
    [Export] public float AutoCloseSeconds = 5f;

    public DoorState State { get; private set; } = DoorState.Closed;

    // Dual power rails - DM parity is "still works if either circuit is
    // live," not a single powered/unpowered flag. Both default on; either
    // being cut alone leaves the door working normally.
    public bool MainPowered { get; private set; } = true;
    public bool BackupPowered { get; private set; } = true;
    private bool IsPowered => MainPowered || BackupPowered;

    // Floor bolts - dropped, the door won't open for power or a bump, only
    // a bolt-cutting tool interaction (Phase 4) or ForceOpen() can move it.
    public bool IsBolted { get; private set; }

    // Welded shut - same refusal as bolts, cleared only by cutting the weld
    // (also Phase 4). Bolts and welds are independent; either alone blocks
    // a normal Open().
    public bool IsWelded { get; private set; }

    // IDenseStructure - dense while fully closed or in the act of closing
    // (destroyed is never dense - see OnDestroyed); density flips the
    // instant a close begins, not once the animation finishes, so nothing
    // can dash through a mid-close door.
    public bool IsDense => !IsDestroyed && State is DoorState.Closed or DoorState.Closing;

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

    // Normal open - refuses while bolted, welded, or fully unpowered, same
    // as a real airlock's own access-denied buzz. See ForceOpen() for the
    // one case (a crowbar on an unpowered-but-not-bolted/welded door) that's
    // meant to bypass this.
    public void Open()
    {
        if (!Multiplayer.IsServer() || State is DoorState.Open or DoorState.Opening) return;
        if (IsBolted || IsWelded || !IsPowered) return;

        BeginOpen();
    }

    // Crowbar-style manual forced entry - bypasses the power check (that's
    // the whole point of forcing an unpowered door) but still respects bolts
    // and welds, matching real airlock behavior: those need their own tool
    // interaction (cut the weld, cut the bolts) before even a crowbar works.
    public void ForceOpen()
    {
        if (!Multiplayer.IsServer() || State is DoorState.Open or DoorState.Opening) return;
        if (IsBolted || IsWelded) return;

        BeginOpen();
    }

    private void BeginOpen()
    {
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

    public void SetBolted(bool bolted)
    {
        if (!Multiplayer.IsServer() || IsBolted == bolted) return;
        IsBolted = bolted;
        _log?.Log("DOOR", $"{AtomName} at {GridCell} bolts {(bolted ? "dropped" : "raised")}");
        SyncFlagsToClients();
    }

    public void SetWelded(bool welded)
    {
        if (!Multiplayer.IsServer() || IsWelded == welded) return;
        IsWelded = welded;
        _log?.Log("DOOR", $"{AtomName} at {GridCell} {(welded ? "welded shut" : "weld cut")}");
        SyncFlagsToClients();
    }

    public void SetPower(bool mainPowered, bool backupPowered)
    {
        if (!Multiplayer.IsServer() || (MainPowered == mainPowered && BackupPowered == backupPowered)) return;
        MainPowered = mainPowered;
        BackupPowered = backupPowered;
        _log?.Log("DOOR", $"{AtomName} at {GridCell} power: main={mainPowered} backup={backupPowered}");
        SyncFlagsToClients();
    }

    // A destroyed door has nothing left to open/close/bolt - it's wreckage,
    // permanently open and non-dense (see IsDense). No BaseTurf-style
    // reveal-a-different-object here: unlike a wall, a destroyed door isn't
    // hiding another structure underneath it, it's just gone.
    protected override void OnDestroyed()
    {
        State = DoorState.Open;
        UpdateVisual();
        _log?.Log("DOOR", $"{AtomName} at {GridCell} destroyed");

        if (Multiplayer.HasMultiplayerPeer() && Multiplayer.IsServer())
        {
            Rpc(nameof(SyncState), (int)State);
        }
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

    private void SyncFlagsToClients()
    {
        UpdateVisual();
        if (Multiplayer.HasMultiplayerPeer() && Multiplayer.IsServer())
        {
            Rpc(nameof(SyncFlags), IsBolted, IsWelded, MainPowered, BackupPowered);
        }
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false)]
    private void SyncFlags(bool bolted, bool welded, bool mainPowered, bool backupPowered)
    {
        IsBolted = bolted;
        IsWelded = welded;
        MainPowered = mainPowered;
        BackupPowered = backupPowered;
        UpdateVisual();
    }

    // Single-sprite swap, same as every other DmiSheet consumer in this
    // codebase (Item, Turf) - no true multi-layer overlay compositing exists
    // yet, so simultaneous bolted+welded shows welded (the more severe of
    // the two) rather than blending both.
    private void UpdateVisual()
    {
        if (_visual == null || IconSheetPath == "") return;

        var iconState = State switch
        {
            _ when IsWelded => "welded",
            _ when IsBolted && State == DoorState.Closed => "door_locked",
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
