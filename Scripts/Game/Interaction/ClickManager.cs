using Godot;
using GodotStation.Core.World;
using GodotStation.Game.Mobs;

namespace GodotStation.Game.Interaction;

// Mouse-click front end for interaction, ported from the old prototype
// (its own original code) - the missing "point-and-click" input path
// alongside PlayerMob's existing facing-based verbs (DoAttack/DoExamine
// already cover "activate"/"peek" against whatever's directly ahead).
// Connection rebuild vs. the old version:
//  - GridSystem -> WorldGrid; no PhysicsPointQueryParameters2D world-item
//    click/drag/double-click detection - Item isn't a physics collider in
//    this codebase, pickup is the "pickup"/"quick_pickup" keys
//    (PlayerMob.DoPickupAt/DoPickup) instead of clicking the item itself.
//  - Fireman carry's drag gesture (mouse-down, hold, drag, release) is
//    simplified to a discrete Ctrl-click on an already-grabbed target's
//    cell - no drag-state tracking exists elsewhere in this codebase to
//    match against.
//  - Shift-click examine and mouse-driven facing-on-empty-click are
//    dropped - examine already has a facing-independent binding ("peek"
///   -> PlayerMob.DoExamine) and facing is driven by movement input only,
//    not intercepted at click time.
//  - IMobSystem -> IMobComponent; RPC dispatch goes through PlayerMob's
//    existing HudRequest*/RequestInteractAt entry points rather than its
//    own parallel ServerGrabClick/ServerInteract/... RPC set.
public partial class ClickManager : Node, IMobComponent
{
    private PlayerMob? _owner;
    private PlayerInteractionSystem? _interaction;

    public void Initialize(Mob mob)
    {
        _owner = mob as PlayerMob;
        _interaction = mob.GetMobComponent<PlayerInteractionSystem>();
    }

    public void Cleanup() { }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (_owner == null || Multiplayer.GetUniqueId() != _owner.OwnerPeerId) return;
        if (_owner.GetMobComponent<MobStateSystem>()?.State != MobState.Standing) return;

        if (@event is not InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left }) return;

        var clickPos = _owner.GetGlobalMousePosition();
        var targetCell = new Vector2I(
            Mathf.FloorToInt(clickPos.X / WorldGrid.DefaultCellSize),
            Mathf.FloorToInt(clickPos.Y / WorldGrid.DefaultCellSize));

        if (targetCell == _owner.GridCell) return;

        if (Input.IsKeyPressed(Key.Ctrl))
        {
            if (_interaction?.IsPulling() == true && _interaction.GetPulling()?.GridCell == targetCell)
            {
                _owner.HudRequestFiremanCarry();
            }
            else
            {
                _owner.HudRequestGrabAt(targetCell);
            }
        }
        else
        {
            _owner.HudRequestInteractAt(targetCell);
        }

        GetViewport().SetInputAsHandled();
    }
}
