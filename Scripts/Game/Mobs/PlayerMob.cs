using Godot;
using GodotStation.Core.Assets;
using GodotStation.Core.Net;
using GodotStation.Core.World;
using GodotStation.Game.Mobs.Health;
using GodotStation.Game.Objects.Items;

namespace GodotStation.Game.Mobs;

// A human-controlled Mob. Movement is server-authoritative: this node's
// multiplayer authority is always the server, regardless of which client it
// represents (OwnerPeerId) - the owning client only sends its desired
// direction and renders the server's confirmed position back. This mirrors
// ucfss13's own client-dumb/server-authoritative model in spirit (an
// original design choice appropriate to a server-hosted round, not a copy
// of its code).
public partial class PlayerMob : Mob
{
    private const float SyncIntervalSeconds = 0.05f;

    // HUD-facing signals - GDScript UI binds to these, never to
    // health/inventory component internals directly. Emitted only from the
    // Sync* RPC receivers below (all CallLocal=true), so host and remote
    // clients update their HUD through the exact same path instead of one
    // local-direct branch and one networked branch.
    [Signal] public delegate void HudHealthChangedEventHandler(float integrity, float maxIntegrity);
    [Signal] public delegate void HudConsciousStateChangedEventHandler(int state);
    [Signal] public delegate void HudHandsChangedEventHandler(string hand0Path, string hand0State, string hand1Path, string hand1State, int activeHand);
    [Signal] public delegate void HudIntentChangedEventHandler(int intent);
    [Signal] public delegate void HudEquipmentChangedEventHandler(string slot, string sheetPath, string state);

    // Placeholder art source until Phase 4's real marine gear/species scenes
    // exist - "marine spriting template" is ucfss13's own reference/base
    // body state, reused here the same way the rest of Assets/Icons is
    // (converted sheet, see Tools/dmi_convert.py), not hand-drawn.
    private const string BodySheetPath = "res://Icons/mob/humans/human.png";
    private const string BodyState = "marine spriting template";

    // Matches DmiSheet's direction key strings and doubles as the wire
    // format for facing sync (index into this array, not the string itself).
    private static readonly string[] FacingNames = { "south", "north", "east", "west" };

    public long OwnerPeerId { get; set; }

    private MovementController? _movementController;
    private Camera2D? _camera;
    private MobAppearance? _appearance;
    private Inventory? _inventory;
    private HealthSystem? _health;
    private MobStateSystem? _mobState;
    private FireSystem? _fire;
    private Interaction.PlayerInteractionSystem? _interaction;

    // Defaults to Harm rather than SS13's usual Help default - there's no
    // intent indicator in the HUD yet, and defaulting to a no-damage intent
    // would make combat look broken to anyone testing without already
    // knowing to press 4 first. Revisit once there's a real intent HUD.
    private Intent _currentIntent = Intent.Harm;

    // Server-side only: latest direction the owning client asked to move in.
    private Vector2 _pendingDirection;
    private float _syncAccumulator;
    private int _facingIndex; // committed/visible facing - synced to clients
    private int _desiredFacingIndex; // latest input intent - not yet committed if mid-tween
    private int _lastAppliedFacing = -1; // client-side: avoid redundant texture swaps

    public override void _Ready()
    {
        base._Ready(); // Mob's component auto-collection - must run

        _movementController = GetNodeOrNull<MovementController>("MovementController");
        _camera = GetNodeOrNull<Camera2D>("Camera2D");
        _appearance = GetNodeOrNull<MobAppearance>("Appearance");
        _inventory = GetNodeOrNull<Inventory>("Inventory");
        _health = GetMobComponent<HealthSystem>();
        _mobState = GetMobComponent<MobStateSystem>();
        _fire = GetMobComponent<FireSystem>();
        if (_health != null)
        {
            _health.HealthChanged += OnHealthChanged;
            _health.StatusMessage += OnHealthStatusMessage;
        }
        if (_mobState != null) _mobState.StateChanged += OnMobStateChanged;
        if (_fire != null) _fire.StatusMessage += OnHealthStatusMessage;
        _interaction = GetMobComponent<Interaction.PlayerInteractionSystem>();
        if (_interaction != null) _interaction.StatusMessage += OnHealthStatusMessage;
        if (_inventory != null)
        {
            _inventory.HandsChanged += OnHandsChanged;
            _inventory.EquipmentChanged += OnEquipmentChanged;
        }

        if (_camera != null)
        {
            _camera.Enabled = Multiplayer.GetUniqueId() == OwnerPeerId;
        }

        _appearance?.SetLayer("body", BodySheetPath, BodyState);
    }

    public override void _PhysicsProcess(double delta)
    {
        if (OwnerPeerId != 0 && Multiplayer.GetUniqueId() == OwnerPeerId)
        {
            ReadLocalInput();
        }

        if (Multiplayer.IsServer())
        {
            ServerTick((float)delta);
        }
    }

    private void ReadLocalInput()
    {
        var direction = Vector2.Zero;
        if (Input.IsActionPressed("up")) direction.Y -= 1;
        if (Input.IsActionPressed("down")) direction.Y += 1;
        if (Input.IsActionPressed("left")) direction.X -= 1;
        if (Input.IsActionPressed("right")) direction.X += 1;
        direction = direction.Normalized();

        // The host controlling their own mob is already the authority - call
        // straight through rather than RpcId'ing to itself. A self-targeted
        // RPC isn't a real network hop, and GetRemoteSenderId() doesn't
        // reliably report the local peer's own id in that case, which would
        // fail SetDirection's sender check below and silently eat all input.
        if (Multiplayer.IsServer())
        {
            ApplyDirection(direction);
        }
        else
        {
            RpcId(1, nameof(SetDirection), direction);
        }

        // Same self-vs-network shape as movement above: the host's own
        // button presses call straight through rather than RpcId'ing to
        // itself, since a self-targeted RPC would fail the sender check in
        // Request*'s guard below.
        if (Input.IsActionJustPressed("switch_hand"))
        {
            if (Multiplayer.IsServer()) DoSwitchHand(); else RpcId(1, nameof(RequestSwitchHand));
        }
        if (Input.IsActionJustPressed("quick_pickup"))
        {
            if (Multiplayer.IsServer()) DoPickup(); else RpcId(1, nameof(RequestPickup));
        }
        if (Input.IsActionJustPressed("pickup"))
        {
            var clickedCell = WorldToCell(GetGlobalMousePosition());
            if (Multiplayer.IsServer()) DoPickupAt(clickedCell); else RpcId(1, nameof(RequestPickupAt), clickedCell);
        }
        if (Input.IsActionJustPressed("drop"))
        {
            if (Multiplayer.IsServer()) DoDrop(); else RpcId(1, nameof(RequestDrop));
        }
        // "peek" is otherwise-unused in the inherited input map - reused here
        // as the examine verb rather than adding a new bound action.
        if (Input.IsActionJustPressed("peek"))
        {
            if (Multiplayer.IsServer()) DoExamine(); else RpcId(1, nameof(RequestExamine));
        }
        if (Input.IsActionJustPressed("throw"))
        {
            if (Multiplayer.IsServer()) DoThrow(); else RpcId(1, nameof(RequestThrow));
        }
        if (Input.IsActionJustPressed("activate"))
        {
            if (Multiplayer.IsServer()) DoAttack(); else RpcId(1, nameof(RequestAttack));
        }
        if (Input.IsActionJustPressed("intent_help")) SendIntent(Intent.Help);
        if (Input.IsActionJustPressed("intent_disarm")) SendIntent(Intent.Disarm);
        if (Input.IsActionJustPressed("intent_grab")) SendIntent(Intent.Grab);
        if (Input.IsActionJustPressed("intent_harm")) SendIntent(Intent.Harm);
        // Temporary test hook until Phase 3b delivers real damage sources
        // (combat) - "debug_short_circuit" is otherwise unused. Remove once
        // something else can actually deal damage.
        if (Input.IsActionJustPressed("debug_short_circuit"))
        {
            if (Multiplayer.IsServer()) DoDebugDamage(); else RpcId(1, nameof(RequestDebugDamage));
        }
    }

    private void SendIntent(Intent intent)
    {
        if (Multiplayer.IsServer()) DoSetIntent((int)intent); else RpcId(1, nameof(RequestSetIntent), (int)intent);
    }

    private bool IsIncapacitated() => _mobState != null && _mobState.IsIncapacitated();

    // Public entry points for the GDScript HUD - it shouldn't need to know
    // about the private Request*/Do* self-vs-network RPC plumbing above,
    // and calling a private C# RPC method by name from GDScript isn't
    // something to rely on (only public API is a safe cross-language contract).
    public void HudRequestSetIntent(int intent) => SendIntent((Intent)intent);

    public void HudRequestDrop()
    {
        if (Multiplayer.IsServer()) DoDrop(); else RpcId(1, nameof(RequestDrop));
    }

    public void HudRequestSwitchHand()
    {
        if (Multiplayer.IsServer()) DoSwitchHand(); else RpcId(1, nameof(RequestSwitchHand));
    }

    // Clicking an equipment slot in the HUD: empty slot -> try to wear the
    // active-hand item there; occupied slot -> take it back into a hand.
    public void HudRequestEquip(string slot)
    {
        if (Multiplayer.IsServer()) DoEquip(slot); else RpcId(1, nameof(RequestEquip), slot);
    }

    public void HudRequestUnequip(string slot)
    {
        if (Multiplayer.IsServer()) DoUnequip(slot); else RpcId(1, nameof(RequestUnequip), slot);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestEquip(string slot)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoEquip(slot);
    }

    private void DoEquip(string slot)
    {
        if (IsIncapacitated()) return;
        _inventory?.EquipActiveHand(slot);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestUnequip(string slot)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoUnequip(slot);
    }

    private void DoUnequip(string slot)
    {
        if (IsIncapacitated()) return;
        _inventory?.UnequipToHand(slot);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestSwitchHand()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoSwitchHand();
    }

    private void DoSwitchHand()
    {
        if (IsIncapacitated()) return;
        _inventory?.SwitchHand();
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestPickup()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoPickup();
    }

    // "quick_pickup" (F) - grabs from your own tile only, no aiming needed.
    private void DoPickup() => DoPickupAt(GridCell);

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestPickupAt(Vector2I cell)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoPickupAt(cell);
    }

    // The actual SS13-authentic path: left-click an item on the ground
    // (your own tile or an adjacent one) to pick it up.
    private void DoPickupAt(Vector2I cell)
    {
        if (IsIncapacitated()) return;
        if (_inventory == null || !_inventory.HasFreeHand()) return;

        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        if (cell != GridCell && !worldGrid.IsAdjacent(cell, GridCell)) return;

        Item? found = null;
        foreach (var occupant in worldGrid.GetOccupants(cell))
        {
            if (occupant is Item item) { found = item; break; }
        }
        if (found == null) return;

        found.RemoveFromWorld();
        _inventory.TryStore(found);
        AddChild(found);
        found.Visible = false;
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestDrop()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoDrop();
    }

    private void DoDrop()
    {
        if (IsIncapacitated()) return;
        if (_inventory == null) return;

        var item = _inventory.TakeActiveItem();
        if (item == null) return;

        if (item.GetParent() == this) RemoveChild(item);
        item.PlaceInWorld(Position);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestThrow()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoThrow();
    }

    private const int ThrowRangeCells = 5;

    private void DoThrow()
    {
        if (IsIncapacitated()) return;
        if (_inventory == null) return;

        var item = _inventory.TakeActiveItem();
        if (item == null) return;

        if (item.GetParent() == this) RemoveChild(item);
        item.ThrowInDirection(GridCell, FacingToCellDirection(_facingIndex), ThrowRangeCells);
    }

    private static Vector2I WorldToCell(Vector2 worldPosition) => new(
        Mathf.FloorToInt(worldPosition.X / WorldGrid.DefaultCellSize),
        Mathf.FloorToInt(worldPosition.Y / WorldGrid.DefaultCellSize));

    private static Vector2I FacingToCellDirection(int facingIndex) => facingIndex switch
    {
        0 => new Vector2I(0, 1),  // south
        1 => new Vector2I(0, -1), // north
        2 => new Vector2I(1, 0),  // east
        _ => new Vector2I(-1, 0), // west
    };

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestExamine()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoExamine();
    }

    // Examines whatever's in the active hand; falls back to another mob
    // standing on the same tile, then to self. Range/line-of-sight checks
    // are a later concern (Phase 3's minimum is "get examine text at all").
    private void DoExamine()
    {
        if (IsIncapacitated()) return;
        var chat = GetNode<ChatManager>("/root/ChatManager");

        var activeItem = _inventory?.GetActiveItem();
        if (activeItem != null)
        {
            chat.SendSystemMessage(OwnerPeerId, activeItem.Examine());
            return;
        }

        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        foreach (var occupant in worldGrid.GetOccupants(GridCell))
        {
            if (occupant != this)
            {
                chat.SendSystemMessage(OwnerPeerId, occupant.Examine());
                return;
            }
        }

        chat.SendSystemMessage(OwnerPeerId, Examine());
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestDebugDamage()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoDebugDamage();
    }

    private void DoDebugDamage() => _health?.ApplyDamage(DamageType.Brute, 15f, "Debug");

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestSetIntent(int intent)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoSetIntent(intent);
    }

    private void DoSetIntent(int intent)
    {
        _currentIntent = (Intent)intent;
        Rpc(nameof(SyncHudIntent), intent);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestAttack()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoAttack();
    }

    // Melee interactions share a cooldown (ported behavior: the old
    // prototype throttled InteractWithMob to one per second).
    private const float InteractionCooldownSeconds = 1.0f;
    private float _nextInteractionTime;

    // "Attack whatever's directly ahead" - the facing-based path bound to
    // the "activate" key. If a mob is adjacent in the faced direction,
    // resolve melee by intent (CombatResolver, ported logic); otherwise, if
    // holding a Gun, fire down that lane; otherwise try a self-equip.
    private void DoAttack()
    {
        if (IsIncapacitated()) return;

        var direction = FacingToCellDirection(_facingIndex);
        var targetCell = GridCell + direction;
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");

        var targetMob = FindMobAt(worldGrid, targetCell);
        if (targetMob != null)
        {
            InteractWithMob(targetMob);
            return;
        }

        if (_inventory?.GetActiveItem() is Gun gun && gun.Fire(GridCell, direction, out var hitMob) && hitMob != null)
        {
            hitMob.GetMobComponent<HealthSystem>()?.ApplyDamage(DamageType.Brute, gun.Damage, AtomName);
            return;
        }

        // Nothing in front and not holding a gun - "activate" on a wearable
        // held item quick-equips it (ucfss13's click-self-to-equip; no-ops
        // harmlessly for anything that isn't wearable).
        _inventory?.TryEquipActiveHandAnySlot();
    }

    // Click-targeted variant (ClickManager) - same intent resolution as
    // DoAttack, just against an explicit adjacent cell (from the mouse)
    // instead of whatever's directly ahead. No gun-fire/auto-equip fallback
    // - those stay facing-only verbs.
    private void DoInteractAt(Vector2I targetCell)
    {
        if (IsIncapacitated()) return;

        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        if (targetCell != GridCell && !worldGrid.IsAdjacent(GridCell, targetCell)) return;

        var targetMob = FindMobAt(worldGrid, targetCell);
        if (targetMob != null) InteractWithMob(targetMob);
    }

    private static Mob? FindMobAt(WorldGrid worldGrid, Vector2I cell)
    {
        foreach (var occupant in worldGrid.GetOccupants(cell))
        {
            if (occupant is Mob mob) return mob;
        }
        return null;
    }

    private void InteractWithMob(Mob targetMob)
    {
        var now = Time.GetTicksMsec() / 1000f;
        if (now < _nextInteractionTime) return;
        _nextInteractionTime = now + InteractionCooldownSeconds;

        var feedback = Interaction.CombatResolver.Resolve(this, targetMob, _currentIntent, _inventory?.GetActiveItem());
        if (feedback != "")
        {
            GetNode<ChatManager>("/root/ChatManager").SendSystemMessage(OwnerPeerId, feedback);
        }
    }

    // ── Mouse-click entry points (ClickManager) ──────────────────────────
    public void HudRequestInteractAt(Vector2I targetCell)
    {
        if (Multiplayer.IsServer()) DoInteractAt(targetCell); else RpcId(1, nameof(RequestInteractAt), targetCell);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestInteractAt(Vector2I targetCell)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoInteractAt(targetCell);
    }

    public void HudRequestFiremanCarry()
    {
        if (Multiplayer.IsServer()) _interaction?.StartFiremanCarry(); else RpcId(1, nameof(RequestFiremanCarry));
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestFiremanCarry()
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        _interaction?.StartFiremanCarry();
    }

    // Ctrl-click: always attempts a grab, regardless of current intent
    // (matches the old prototype's dedicated grab gesture).
    public void HudRequestGrabAt(Vector2I targetCell)
    {
        if (Multiplayer.IsServer()) DoGrabAt(targetCell); else RpcId(1, nameof(RequestGrabAt), targetCell);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestGrabAt(Vector2I targetCell)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;
        DoGrabAt(targetCell);
    }

    private void DoGrabAt(Vector2I targetCell)
    {
        if (IsIncapacitated() || _interaction == null) return;

        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        if (!worldGrid.IsAdjacent(GridCell, targetCell)) return;

        var targetMob = FindMobAt(worldGrid, targetCell);
        if (targetMob != null) _interaction.HandleGrabIntent(targetMob);
    }

    // Server-side helper for CombatResolver's disarm: drops whatever is in
    // the active hand regardless of incapacitation gating (being disarmed
    // isn't voluntary).
    public void ForceDropActiveItem()
    {
        if (!Multiplayer.IsServer() || _inventory == null) return;

        var item = _inventory.TakeActiveItem();
        if (item == null) return;

        if (item.GetParent() == this) RemoveChild(item);
        item.PlaceInWorld(Position);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered)]
    private void SetDirection(Vector2 direction)
    {
        if (!Multiplayer.IsServer()) return;
        if (Multiplayer.GetRemoteSenderId() != OwnerPeerId) return;

        ApplyDirection(direction);
    }

    private void ApplyDirection(Vector2 direction)
    {
        if (IsIncapacitated()) direction = Vector2.Zero;

        var previous = _pendingDirection;
        _pendingDirection = direction;

        var directionChanged = direction != Vector2.Zero && direction != previous;

        // Only updates the *desired* facing, not the visible one. Concrete
        // example this needs to satisfy: mid-tween sliding north, player
        // presses west - the sprite keeps facing north until that north
        // tween actually finishes, and only turns to face west once the
        // west step itself begins. ServerTick below commits _desiredFacingIndex
        // to the visible _facingIndex only once the previous tween has landed.
        if (directionChanged)
        {
            _desiredFacingIndex = DirectionToFacingIndex(direction);
        }

        // Grid mode steps discretely on a direction change rather than every
        // tick - continuous stepping while held is handled by TryStepGrid's
        // own re-entrancy guard once movement animation finishes.
        if (MovementController.GlobalMode == MovementMode.Grid && directionChanged)
        {
            TryGridStep(direction);
        }
    }

    private static int DirectionToFacingIndex(Vector2 direction)
    {
        // Grid mode is already cardinal-only by the time this runs; Pixel
        // mode can be diagonal, so pick whichever axis dominates.
        if (Mathf.Abs(direction.Y) >= Mathf.Abs(direction.X))
        {
            return direction.Y > 0 ? 0 : 1; // south : north
        }
        return direction.X > 0 ? 2 : 3; // east : west
    }

    private void ServerTick(float delta)
    {
        if (_movementController == null) return;

        if (MovementController.GlobalMode == MovementMode.Grid)
        {
            // Captured before this tick's own TryGridStep call - reflects
            // whether a step was still animating as of the end of the
            // previous frame, which is what facing should actually wait on.
            var wasMoving = _movementController.IsMoving;

            // Held-direction re-attempt: TryStepGrid no-ops mid-animation, so
            // this just keeps walking while a key stays down.
            if (_pendingDirection != Vector2.Zero) TryGridStep(_pendingDirection);

            if (!wasMoving) _facingIndex = _desiredFacingIndex;
        }
        else
        {
            _movementController.MovePixel(_pendingDirection, delta);
            _facingIndex = _desiredFacingIndex; // Pixel mode has no tween to wait on
        }

        ApplyFacing(_facingIndex); // server's own local visual - SyncFacing below is CallLocal=false

        _syncAccumulator += delta;
        if (_syncAccumulator < SyncIntervalSeconds) return;
        _syncAccumulator = 0f;
        Rpc(nameof(SyncPosition), Position);
        Rpc(nameof(SyncFacing), _facingIndex);
    }

    // These fire only server-side (the health stack's mutators no-op
    // off-server) - broadcast so every peer's copy of this mob (and its
    // HUD) reflects the change, not just the server's own local view.
    // The Hud ABI ships the coarse ConsciousState bucket, derived from the
    // richer MobState - this signal set is a frozen contract HUD code binds
    // to (see plan), regardless of which HUD scene consumes it.
    private void OnMobStateChanged(int newState, int oldState)
        => Rpc(nameof(SyncHudConsciousState), (int)MobStateSystem.ToConsciousState((MobState)newState));

    private void OnHealthChanged(float currentHealth, float maxHealth) => Rpc(nameof(SyncHudHealth), currentHealth, maxHealth);

    private void OnHealthStatusMessage(string text)
    {
        if (!Multiplayer.IsServer()) return;
        GetNode<ChatManager>("/root/ChatManager").SendSystemMessage(OwnerPeerId, text);
    }

    private void OnHandsChanged()
    {
        if (_inventory == null) return;

        var hand0 = _inventory.GetHand(0);
        var hand1 = _inventory.GetHand(1);
        Rpc(nameof(SyncHudHands),
            hand0?.IconSheetPath ?? "", hand0?.IconState ?? "",
            hand1?.IconSheetPath ?? "", hand1?.IconState ?? "",
            _inventory.ActiveHand);

        // In-hand appearance layers (hand 0 = right). Separate RPC rather
        // than widening the frozen SyncHudHands payload.
        Rpc(nameof(SyncInhandVisuals),
            hand0?.Data?.OnMobSheetPath ?? "", hand0?.Data?.InhandRightState ?? "",
            hand1?.Data?.OnMobSheetPath ?? "", hand1?.Data?.InhandLeftState ?? "");
    }

    // Fires server-side on worn-slot changes; broadcasts the worn-layer
    // visual to every peer's copy of this mob.
    private void OnEquipmentChanged(string slot)
    {
        if (_inventory == null) return;
        var item = _inventory.GetEquipped(slot);
        Rpc(nameof(SyncEquipmentVisual), slot, item?.Data?.OnMobSheetPath ?? "", item?.Data?.WornState ?? "");
        Rpc(nameof(SyncHudEquipment), slot, item?.IconSheetPath ?? "", item?.IconState ?? "");
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncHudEquipment(string slot, string sheetPath, string state)
        => EmitSignal(SignalName.HudEquipmentChanged, slot, sheetPath, state);

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncEquipmentVisual(string slot, string sheetPath, string state)
    {
        // Slots with no on-mob layer (id/belt/pouches/ears/suit storage for
        // now) simply don't match a MobAppearance layer name and no-op.
        _appearance?.SetLayer(slot, sheetPath, state);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncInhandVisuals(string rightSheet, string rightState, string leftSheet, string leftState)
    {
        _appearance?.SetLayer("inhand_right", rightSheet, rightState);
        _appearance?.SetLayer("inhand_left", leftSheet, leftState);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncHudConsciousState(int state)
    {
        EmitSignal(SignalName.HudConsciousStateChanged, state);

        // Placeholder feedback until real death/unconscious sprites exist -
        // tint + prone rotation so the state is at least visible on every peer.
        if (_appearance == null) return;
        var conscious = (ConsciousState)state;
        _appearance.SetTint(conscious switch
        {
            ConsciousState.Dead => new Color(0.4f, 0.4f, 0.4f, 0.6f),
            ConsciousState.Unconscious => new Color(0.7f, 0.7f, 0.7f, 0.85f),
            _ => Colors.White,
        });
        _appearance.SetProne(conscious != ConsciousState.Conscious);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncHudHealth(float integrity, float maxIntegrity) => EmitSignal(SignalName.HudHealthChanged, integrity, maxIntegrity);

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncHudHands(string hand0Path, string hand0State, string hand1Path, string hand1State, int activeHand)
        => EmitSignal(SignalName.HudHandsChanged, hand0Path, hand0State, hand1Path, hand1State, activeHand);

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SyncHudIntent(int intent) => EmitSignal(SignalName.HudIntentChanged, intent);

    private void ApplyFacing(int facingIndex)
    {
        if (_appearance == null) return;
        if (facingIndex == _lastAppliedFacing) return;

        _lastAppliedFacing = facingIndex;
        _appearance.SetFacing(facingIndex);
    }

    private void TryGridStep(Vector2 direction)
    {
        var step = new Vector2I(Mathf.RoundToInt(direction.X), Mathf.RoundToInt(direction.Y));

        // Grid mode is 4-directional only, matching classic tile-based SS13
        // movement - no diagonal steps. Pixel mode (MovePixel, above) is
        // unaffected and stays free 8-directional; that contrast is the
        // point of offering both. Vertical wins when both axes are held;
        // an arbitrary but consistent tie-break.
        if (step.X != 0 && step.Y != 0) step.X = 0;

        if (step != Vector2I.Zero) _movementController!.TryStepGrid(step);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered)]
    private void SyncPosition(Vector2 position)
    {
        Position = position;
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered)]
    private void SyncFacing(int facingIndex)
    {
        ApplyFacing(facingIndex);
    }
}
