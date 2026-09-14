using Godot;
using GodotStation.Core.Atoms;

namespace GodotStation.Core.World;

public enum MovementMode
{
    Grid,
    Pixel,
}

// The only code allowed to know which movement mode is active. Both
// backends write the same movable's authoritative cell through
// WorldGrid.MoveOccupant - everything upstream (combat range, interaction,
// pathfinding) is written once against WorldGrid's API and never needs to
// know which backend produced a given position. See the M2 roadmap's
// Grid/Pixel Toggle rule (§4.2) - any other system branching on movement
// mode is almost certainly a bug.
//
// Mode is meant to be a per-server toggle (set GlobalMode once at startup),
// not per-entity - mixing modes between entities isn't a supported case.
public partial class MovementController : Node
{
    public static MovementMode GlobalMode = MovementMode.Grid;

    [Export] public float GridCellSize = 32f;

    // Real DM/BYOND mobs have no glide/tween at all (glide_size 0 - a move
    // just snaps the mob's screen position to the new tile the instant it
    // succeeds) and are instead paced by a fixed post-move cooldown before
    // the next step is accepted (/client/Move's next_movement gate). This
    // is that cooldown, not an animation duration - confirmed against the
    // real source (human_movement.dm, mob.dm) rather than assumed; base
    // running human delay there is roughly 0.2-0.3s before gear/wounds add
    // more, which per-item/wound modifiers don't exist to layer on yet.
    [Export] public float GridMoveDelaySeconds = 0.25f;
    [Export] public float PixelSpeed = 160f;

    // Independent slow-down channels so their owners never overwrite each
    // other: SpeedMultiplier belongs to HealthSystem (pain/status effects),
    // StateSpeedMultiplier to MobStateSystem (prone/stunned/...),
    // InteractionSpeedMultiplier to PlayerInteractionSystem (grabbing/
    // being grabbed). Effective speed is their product; at 0 the mob can't
    // move at all.
    public float SpeedMultiplier { get; set; } = 1f;
    public float StateSpeedMultiplier { get; set; } = 1f;
    public float InteractionSpeedMultiplier { get; set; } = 1f;

    private float EffectiveSpeedMultiplier => Mathf.Max(0f, SpeedMultiplier * StateSpeedMultiplier * InteractionSpeedMultiplier);

    private MovableAtom? _owner;
    private WorldGrid? _worldGrid;
    private float _moveCooldownRemaining;

    public override void _Ready()
    {
        _owner = GetParent() as MovableAtom;
        _worldGrid = GetNodeOrNull<WorldGrid>("/root/WorldGrid");

        if (_owner == null)
        {
            GD.PrintErr("[MovementController] must be a child of a MovableAtom.");
            return;
        }
        if (_worldGrid == null)
        {
            GD.PrintErr("[MovementController] WorldGrid autoload not found at /root/WorldGrid.");
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_owner == null || _worldGrid == null) return;

        switch (GlobalMode)
        {
            case MovementMode.Grid:
                if (_moveCooldownRemaining > 0f) _moveCooldownRemaining -= (float)delta;
                break;
            case MovementMode.Pixel:
                TickPixelMode();
                break;
        }
    }

    // Grid mode: attempts to step exactly one cell in the given direction.
    // No-ops while still on the post-move cooldown or the destination is
    // dense. A successful step snaps Position directly to the new tile -
    // no animation - matching real DM's glide_size-0 movement exactly.
    public bool TryStepGrid(Vector2I direction)
    {
        if (_owner == null || _worldGrid == null || _moveCooldownRemaining > 0f) return false;
        if (EffectiveSpeedMultiplier <= 0f) return false;

        var target = _owner.GridCell + direction;
        if (_worldGrid.IsDense(target))
        {
            // Bump-to-open: a closed door reacts to being walked into rather
            // than just blocking silently, matching ucfss13's own airlock
            // behavior. No cooldown is spent on a blocked attempt - DM only
            // sets its move-delay gate on a move that actually succeeds.
            if (_worldGrid.GetStructure(target) is IBumpable bumpable) bumpable.OnBumped();
            return false;
        }

        _worldGrid.MoveOccupant(_owner, _owner.GridCell, target);
        _owner.Position = CellToWorld(target);
        _moveCooldownRemaining = GridMoveDelaySeconds / EffectiveSpeedMultiplier;
        return true;
    }

    // Pixel mode: continuous movement input, called once per physics frame
    // by whatever reads player/AI input. Actual collision response is left
    // to the owner's own physics body composition - this just applies the
    // requested motion and re-derives the authoritative grid cell afterward.
    public void MovePixel(Vector2 direction, double delta)
    {
        if (_owner == null) return;
        _owner.Position += direction * PixelSpeed * EffectiveSpeedMultiplier * (float)delta;
    }

    private void TickPixelMode()
    {
        if (_owner == null || _worldGrid == null) return;

        var newCell = WorldToCell(_owner.Position);
        if (newCell != _owner.GridCell)
        {
            _worldGrid.MoveOccupant(_owner, _owner.GridCell, newCell);
        }
    }

    // Instantly relocates the owner to a cell - for systems that move a mob
    // without it choosing to move itself (grabbed/carried by another mob).
    // Doesn't touch the move cooldown - being dragged isn't a step this mob
    // took, so it shouldn't affect when its next own step is allowed.
    public void ForceSetCell(Vector2I cell)
    {
        if (_owner == null || _worldGrid == null) return;

        _worldGrid.MoveOccupant(_owner, _owner.GridCell, cell);
        _owner.Position = CellToWorld(cell);
    }

    private Vector2 CellToWorld(Vector2I cell) => new(cell.X * GridCellSize, cell.Y * GridCellSize);

    private Vector2I WorldToCell(Vector2 position) => new(
        Mathf.FloorToInt(position.X / GridCellSize),
        Mathf.FloorToInt(position.Y / GridCellSize)
    );
}
