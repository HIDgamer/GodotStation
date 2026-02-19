using Godot;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class GridSystem : Node
{
	[Export] public Godot.Collections.Dictionary<Vector2I, string> Grid { get; private set; } = new();
	private readonly HashSet<Vector2I> _baseCells = new();
	private readonly Dictionary<Vector2I, List<Node2D>> _entitiesOnTile = new();
	private CollisionManager _collision;

	[Signal] public delegate void ScanCompletedEventHandler(Godot.Collections.Dictionary<Vector2I, string> grid);

	public string GetTileTypeAtCell(Vector2I cell) => Grid.TryGetValue(cell, out var type) ? type : null;
	public void UpdateTile(Vector2I cell, string tileType) => Grid[cell] = tileType;
	
	public Vector2I WorldToGrid(Vector2 worldPos) => new((int)Mathf.Floor(worldPos.X / 32), (int)Mathf.Floor(worldPos.Y / 32));
	public Vector2 GridToWorld(Vector2I gridCell) => new(gridCell.X * 32 + 16, gridCell.Y * 32 + 16);

	public void RegisterEntity(Node2D entity, Vector2I cell)
	{
		if (!_entitiesOnTile.ContainsKey(cell))
			_entitiesOnTile[cell] = new List<Node2D>();
		_entitiesOnTile[cell].Add(entity);
	}

	public void UnregisterEntity(Node2D entity, Vector2I cell)
	{
		if (_entitiesOnTile.TryGetValue(cell, out var entities))
			entities.Remove(entity);
	}

	public List<Node2D> GetEntitiesOnTile(Vector2I cell)
	{
		return _entitiesOnTile.TryGetValue(cell, out var entities) ? entities : new List<Node2D>();
	}

	public override async void _Ready()
	{
		_collision = GetParent().GetNodeOrNull<CollisionManager>("CollisionManager");
		var tempGrid = await Task.Run(() => ScanAllLayers());
		Grid = tempGrid;
		EmitSignal(SignalName.ScanCompleted, Grid);
	}

	private Godot.Collections.Dictionary<Vector2I, string> ScanAllLayers()
	{
		var grid = new Godot.Collections.Dictionary<Vector2I, string>();
		var layers = new[] { ("Base", "base"), ("Ground", "floor"), ("Tag", "tag") };

		foreach (var (group, type) in layers)
			ScanLayerSync(grid, group, type);

		ScanWallLayerSync(grid);
		return grid;
	}

	private void ScanLayerSync(Godot.Collections.Dictionary<Vector2I, string> targetGrid, string groupName, string tileType)
	{
		var nodes = GetTree().GetNodesInGroup(groupName);
		foreach (var node in nodes)
		{
			if (node is not TileMap tileMap) continue;

			for (int layer = 0; layer < tileMap.GetLayersCount(); layer++)
			{
				var cells = tileMap.GetUsedCells(layer);
				foreach (Vector2I cell in cells)
				{
					if (tileMap.GetCellSourceId(layer, cell) == -1) continue;
					var gridCell = WorldToGridCell(tileMap, cell);
					targetGrid[gridCell] = tileType;
					_baseCells.Add(gridCell);
				}
			}
		}
	}

	private void ScanWallLayerSync(Godot.Collections.Dictionary<Vector2I, string> targetGrid)
	{
		var nodes = GetTree().GetNodesInGroup("Wall");
		foreach (var node in nodes)
		{
			if (node is not TileMap tileMap) continue;

			for (int layer = 0; layer < tileMap.GetLayersCount(); layer++)
			{
				var cells = tileMap.GetUsedCells(layer);
				foreach (Vector2I cell in cells)
				{
					if (tileMap.GetCellSourceId(layer, cell) == -1) continue;

					var gridCell = WorldToGridCell(tileMap, cell);
					var tileData = tileMap.GetCellTileData(layer, cell);
					bool isWindow = tileData?.GetCustomData("Window").AsBool() ?? false;

					targetGrid[gridCell] = isWindow ? "window" : "wall";
					_baseCells.Add(gridCell);
				}
			}
		}
	}

	private static Vector2I WorldToGridCell(TileMap tileMap, Vector2I cell)
	{
		var localPos = tileMap.MapToLocal(cell);
		return new((int)Mathf.Floor(localPos.X / 32), (int)Mathf.Floor(localPos.Y / 32));
	}
	
	public bool IsAdjacent(Vector2I tileA, Vector2I tileB)
	{
		if (tileA == tileB)
			return true;
		
		int dist = Mathf.Abs(tileA.X - tileB.X) + Mathf.Abs(tileA.Y - tileB.Y);
		if (dist > 2)
			return false;
		
		if (tileA.X == tileB.X || tileA.Y == tileB.Y)
			return CheckOrthogonalPath(tileA, tileB);
		
		return CheckDiagonalPath(tileA, tileB);
	}
	
	public bool IsAdjacentPos(Vector2 posA, Vector2 posB)
	{
		return IsAdjacent(WorldToGrid(posA), WorldToGrid(posB));
	}
	
	private bool CheckOrthogonalPath(Vector2I from, Vector2I to)
	{
		var dir = to - from;
		
		if (!CanLeaveTile(from, dir))
			return false;
		
		if (!CanEnterTile(to, -dir))
			return false;
		
		return true;
	}
	
	private bool CheckDiagonalPath(Vector2I from, Vector2I to)
	{
		var delta = to - from;
		var dx = new Vector2I(delta.X, 0);
		var dy = new Vector2I(0, delta.Y);
		
		if (CanMoveDiagonal(from, dx, dy))
			return true;
		
		if (CanMoveDiagonal(from, dy, dx))
			return true;
		
		return false;
	}
	
	private bool CanMoveDiagonal(Vector2I from, Vector2I dir1, Vector2I dir2)
	{
		if (!CanLeaveTile(from, dir1))
			return false;
		
		var intermediate = from + dir1;
		if (!IsWalkable(intermediate))
			return false;
		
		if (!CanLeaveTile(intermediate, dir2))
			return false;
		
		var target = intermediate + dir2;
		if (!CanEnterTile(target, -dir2))
			return false;
		
		return true;
	}
	
	private bool CanLeaveTile(Vector2I tile, Vector2I direction)
	{
		return !(_collision?.HasBorderBlocker(tile, direction) ?? false);
	}
	
	private bool CanEnterTile(Vector2I tile, Vector2I direction)
	{
		if (!IsWalkable(tile))
			return false;
		
		return !(_collision?.HasBorderBlocker(tile, direction) ?? false);
	}
	
	public bool IsWalkable(Vector2I tile)
	{
		return _collision?.IsWalkable(tile) ?? true;
	}
	
	public List<Mob> GetBlockingMobs(Vector2I targetTile)
	{
		var blockers = new List<Mob>();
		var entities = GetEntitiesOnTile(targetTile);
		
		foreach (var entity in entities)
		{
			if (entity is Mob mob && mob.Density)
				blockers.Add(mob);
		}
		
		return blockers;
	}
	
	public Mob GetBarrier(Mob attacker, Vector2I targetTile)
	{
		var blockers = GetBlockingMobs(targetTile);
		
		if (blockers.Count == 0)
			return null;
		
		return blockers[GD.RandRange(0, blockers.Count - 1)];
	}
}
