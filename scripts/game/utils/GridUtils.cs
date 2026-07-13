using Godot;

public static class GridUtils
{
	// Grid cell size - matches the tile size used in the game.
	public const float CellSize = 32f;
	
	public static Vector2I WorldToGrid(Vector2 worldPosition)
	{
		return new Vector2I(
			(int)Mathf.Floor(worldPosition.X / CellSize),
			(int)Mathf.Floor(worldPosition.Y / CellSize)
		);
	}
	
	public static Vector2 GridToWorld(Vector2I gridPosition)
	{
		return new Vector2(
			gridPosition.X * CellSize + CellSize / 2,
			gridPosition.Y * CellSize + CellSize / 2
		);
	}
	
	public static Rect2 GetCellBounds(Vector2I gridPosition)
	{
		return new Rect2(
			gridPosition.X * CellSize,
			gridPosition.Y * CellSize,
			CellSize,
			CellSize
		);
	}
	
	public static Vector2I[] GetAdjacentPositions(Vector2I gridPosition)
	{
		return new Vector2I[]
		{
			new Vector2I(gridPosition.X, gridPosition.Y - 1),
			new Vector2I(gridPosition.X, gridPosition.Y + 1),
			new Vector2I(gridPosition.X - 1, gridPosition.Y),
			new Vector2I(gridPosition.X + 1, gridPosition.Y)
		};
	}
	
	public static Vector2 GetGridDirection(Vector2I from, Vector2I to)
	{
		Vector2I delta = to - from;
		return new Vector2(delta.X, delta.Y).Normalized();
	}
	
	public static bool IsPositionInCell(Vector2 worldPosition, Vector2I gridPosition)
	{
		Rect2 cellBounds = GetCellBounds(gridPosition);
		return cellBounds.HasPoint(worldPosition);
	}
	
	public static Vector2I GetClosestGridPosition(Vector2 worldPosition)
	{
		return new Vector2I(
			(int)Mathf.Round(worldPosition.X / CellSize),
			(int)Mathf.Round(worldPosition.Y / CellSize)
		);
	}
	
	public static int GetManhattanDistance(Vector2I pos1, Vector2I pos2)
	{
		return Mathf.Abs(pos1.X - pos2.X) + Mathf.Abs(pos1.Y - pos2.Y);
	}
	
	public static bool AreAdjacent(Vector2I pos1, Vector2I pos2)
	{
		return GetManhattanDistance(pos1, pos2) == 1;
	}
	
	public static Vector2I GetTargetGridPosition(Vector2 worldPosition, Vector2 direction)
	{
		Vector2I currentGrid = WorldToGrid(worldPosition);
		
		if (Mathf.Abs(direction.X) > Mathf.Abs(direction.Y))
		{
			return new Vector2I(
				currentGrid.X + (direction.X > 0 ? 1 : -1),
				currentGrid.Y
			);
		}
		else
		{
			return new Vector2I(
				currentGrid.X,
				currentGrid.Y + (direction.Y > 0 ? 1 : -1)
			);
		}
	}
	
	public static Vector2 SnapToGridCenter(Vector2 worldPosition)
	{
		Vector2I gridPos = WorldToGrid(worldPosition);
		return GridToWorld(gridPos);
	}
	
	public static Vector2 GetMovementDirection(Vector2I from, Vector2I to)
	{
		if (!AreAdjacent(from, to))
			return Vector2.Zero;
			
		return GetGridDirection(from, to);
	}
}
