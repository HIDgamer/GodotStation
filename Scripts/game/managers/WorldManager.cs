using Godot;
using System.Collections.Generic;
using System.Collections.Concurrent;

public partial class WorldManager : Node
{
	[Export] private TileMap _baseLayer;
	public TileMap BaseLayer => _baseLayer;
	
	private ConcurrentQueue<(Vector2I, string)> _tileUpdateQueue = new();
	private const int MaxBatchSize = 20;
	private const float BatchInterval = 0.1f;
	
	private GridSystem _gridSystem;
	private CollisionManager _collisionManager;
	private VisibilitySystem _visibilitySystem;
	private HashSet<Vector2I> _baseCells = new();
	private Timer _batchTimer;
	
	public override void _Ready()
	{
		_baseLayer = GetNodeOrNull<TileMap>("../BaseLayer");
		_gridSystem = GetNodeOrNull<GridSystem>("../GridSystem");
		_collisionManager = GetNodeOrNull<CollisionManager>("../CollisionManager");
		_visibilitySystem = GetNodeOrNull<VisibilitySystem>("../VisibilitySystem");

		if (_gridSystem != null)
		{
			var placedCells = CollectPlacedCells();
			GenerateBases(placedCells);
		}

		_batchTimer = new Timer { WaitTime = BatchInterval, Autostart = true };
		_batchTimer.Timeout += ProcessBatchedUpdates;
		AddChild(_batchTimer);
	}

	public override void _ExitTree()
	{
		_batchTimer?.QueueFree();
	}

	private void ProcessBatchedUpdates()
	{
		if (_tileUpdateQueue.IsEmpty) return;

		int count = 0;
		bool needsRefresh = false;
		while (count < MaxBatchSize && _tileUpdateQueue.TryDequeue(out var update))
		{
			UpdateTileInternal(update.Item1, update.Item2);
			count++;
			needsRefresh = true;
		}

		if (needsRefresh)
			_visibilitySystem?.RefreshGrid();
	}

	private HashSet<Vector2I> CollectPlacedCells()
	{
		var cells = new HashSet<Vector2I>();
		string[] groups = { "Wall", "Ground", "Tag" };
		
		for (int g = 0; g < groups.Length; g++)
		{
			var nodes = GetTree().GetNodesInGroup(groups[g]);
			int nodeCount = nodes.Count;
			for (int n = 0; n < nodeCount; n++)
			{
				if (nodes[n] is TileMap tm)
				{
					var usedCells = tm.GetUsedCells(0);
					int cellCount = usedCells.Count;
					for (int c = 0; c < cellCount; c++)
						cells.Add(WorldToGridCell(tm, (Vector2I)usedCells[c]));
				}
			}
		}
		return cells;
	}

	private Vector2I WorldToGridCell(TileMap tileMap, Vector2I cell)
	{
		Vector2 localPos = tileMap.MapToLocal(cell);
		return new Vector2I(
			(int)Mathf.Floor(localPos.X / 32),
			(int)Mathf.Floor(localPos.Y / 32)
		);
	}

	private void GenerateBases(HashSet<Vector2I> placedCells)
	{
		foreach (var cell in placedCells)
		{
			if (_baseLayer.GetCellSourceId(0, cell) == -1)
			{
				_baseLayer.SetCell(0, cell, 0, Vector2I.Zero);
				_baseCells.Add(cell);
			}
		}
	}

	public void EnsureBase(Vector2I cell)
	{
		if (_baseLayer.GetCellSourceId(0, cell) == -1)
		{
			_baseLayer.SetCell(0, cell, 0, Vector2I.Zero);
			_baseCells.Add(cell);
		}
	}

	public void RemoveTile(Vector2I cell)
	{
		if (_gridSystem.Grid.ContainsKey(cell))
		{
			if (_baseCells.Contains(cell))
			{
				_gridSystem.Grid[cell] = "base";
				_collisionManager.UpdateWalkable(cell, "base");
			}
			else
			{
				_gridSystem.Grid.Remove(cell);
				_collisionManager.UpdateWalkable(cell, null);
			}
			_visibilitySystem?.RefreshGrid();
		}
	}

	public Godot.Collections.Dictionary<Vector2I, string> GetGrid() => _gridSystem?.Grid;

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	public void UpdateTileRpc(Vector2I cell, string tileType)
	{
		if (!IsMultiplayerAuthority()) return;
		_tileUpdateQueue.Enqueue((cell, tileType));
	}

	private void UpdateTileInternal(Vector2I cell, string tileType)
	{
		_gridSystem.Grid[cell] = tileType;
		_collisionManager.UpdateWalkable(cell, tileType);
		if (tileType == "base")
			_baseLayer.SetCell(0, cell, 0, Vector2I.Zero);
	}
}
