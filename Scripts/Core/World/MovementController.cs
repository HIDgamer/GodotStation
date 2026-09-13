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
    [Export] public float GridMoveDuration = 0.15f;
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
    private Vector2 _gridModeTargetPosition;
    private bool _gridModeMoving;

    // Whether a grid-mode step is currently mid-tween. Exposed so callers
    // (e.g. facing/animation logic) can defer visible state changes until
    // the current step actually finishes, rather than reacting instantly to
    // a new direction while still sliding toward the previous cell. Not
    // meaningful in Pixel mode (always false there).
    public bool IsMoving => _gridModeMoving;

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

        _gridModeTargetPosition = _owner.Position;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_owner == null || _worldGrid == null) return;

        switch (GlobalMode)
        {
            case MovementMode.Grid:
                TickGridMode((float)delta);
                break;
            case MovementMode.Pixel:
                TickPixelMode();
                break;
        }
    }

    // Grid mode: attempts to step exactly one cell in the given direction.
    // No-ops if a move is already animating or the destination is dense.
    public bool TryStepGrid(Vector2I direction)
    {
        if (_owner == null || _worldGrid == null || _gridModeMoving) return false;
        if (EffectiveSpeedMultiplier <= 0f) return false;

        var target = _owner.GridCell + direction;
        if (_worldGrid.IsDense(target)) return false;

        _worldGrid.MoveOccupant(_owner, _owner.GridCell, target);
        _gridModeTargetPosition = CellToWorld(target);
        _gridModeMoving = true;
        return true;
    }

    private void TickGridMode(float delta)
    {
        if (!_gridModeMoving || _owner == null) return;

        // An in-flight step always completes even if the multiplier just hit
        // 0 (getting stunned mid-step shouldn't freeze you between tiles) -
        // but a slowed mob slides proportionally slower.
        var speedScale = Mathf.Max(0.25f, EffectiveSpeedMultiplier);
        var toTarget = _gridModeTargetPosition - _owner.Position;
        var step = GridCellSize / GridMoveDuration * speedScale * delta;
        if (toTarget.Length() <= step)
        {
            _owner.Position = _gridModeTargetPosition;
            _gridModeMoving = false;
        }
        else
        {
            _owner.Position += toTarget.Normalized() * step;
        }
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

    // Instantly relocates the owner to a cell without animating a step -
    // for systems that move a mob without it choosing to move itself
    // (grabbed/carried by another mob). Cancels any in-flight step tween,
    // since the cell just changed out from under it.
    public void ForceSetCell(Vector2I cell)
    {
        if (_owner == null || _worldGrid == null) return;

        _worldGrid.MoveOccupant(_owner, _owner.GridCell, cell);
        _gridModeTargetPosition = CellToWorld(cell);
        _owner.Position = _gridModeTargetPosition;
        _gridModeMoving = false;
    }

    private Vector2 CellToWorld(Vector2I cell) => new(cell.X * GridCellSize, cell.Y * GridCellSize);

    private Vector2I WorldToCell(Vector2 position) => new(
        Mathf.FloorToInt(position.X / GridCellSize),
        Mathf.FloorToInt(position.Y / GridCellSize)
    );
}
