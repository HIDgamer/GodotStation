using Godot;

namespace GodotStation.Core.World;

// Pure grid math helpers, ported from the old prototype (its own original
// code - see the reclamation plan). Stateless static functions only:
// anything involving occupancy/density/entities belongs to WorldGrid's API,
// never here.
public static class GridUtils
{
    // Single source of truth for cell size lives on WorldGrid.
    public const float CellSize = WorldGrid.DefaultCellSize;

    public static Vector2I WorldToGrid(Vector2 worldPosition) => new(
        Mathf.FloorToInt(worldPosition.X / CellSize),
        Mathf.FloorToInt(worldPosition.Y / CellSize));

    public static Vector2 GridToWorld(Vector2I gridPosition) => new(
        gridPosition.X * CellSize + CellSize / 2f,
        gridPosition.Y * CellSize + CellSize / 2f);

    public static Rect2 GetCellBounds(Vector2I gridPosition) => new(
        gridPosition.X * CellSize, gridPosition.Y * CellSize, CellSize, CellSize);

    // Cardinal neighbors only (N/S/W/E) - matches 4-directional grid movement.
    public static Vector2I[] GetAdjacentPositions(Vector2I gridPosition) => new[]
    {
        new Vector2I(gridPosition.X, gridPosition.Y - 1),
        new Vector2I(gridPosition.X, gridPosition.Y + 1),
        new Vector2I(gridPosition.X - 1, gridPosition.Y),
        new Vector2I(gridPosition.X + 1, gridPosition.Y),
    };

    public static Vector2 GetGridDirection(Vector2I from, Vector2I to)
    {
        var delta = to - from;
        return new Vector2(delta.X, delta.Y).Normalized();
    }

    public static bool IsPositionInCell(Vector2 worldPosition, Vector2I gridPosition)
        => GetCellBounds(gridPosition).HasPoint(worldPosition);

    public static int GetManhattanDistance(Vector2I a, Vector2I b)
        => Mathf.Abs(a.X - b.X) + Mathf.Abs(a.Y - b.Y);

    // Strict cardinal adjacency (distance exactly 1). Distinct from
    // WorldGrid.IsAdjacent, which is 8-neighbor - pick deliberately.
    public static bool AreCardinallyAdjacent(Vector2I a, Vector2I b)
        => GetManhattanDistance(a, b) == 1;

    // The neighboring cell a world-position entity would step into when
    // moving in `direction` (dominant axis wins, matching movement rules).
    public static Vector2I GetTargetGridPosition(Vector2 worldPosition, Vector2 direction)
    {
        var current = WorldToGrid(worldPosition);
        if (Mathf.Abs(direction.X) > Mathf.Abs(direction.Y))
        {
            return new Vector2I(current.X + (direction.X > 0 ? 1 : -1), current.Y);
        }
        return new Vector2I(current.X, current.Y + (direction.Y > 0 ? 1 : -1));
    }

    public static Vector2 SnapToGridCenter(Vector2 worldPosition)
        => GridToWorld(WorldToGrid(worldPosition));
}
