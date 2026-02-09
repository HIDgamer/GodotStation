using Godot;
using System.Collections.Generic;

[GlobalClass]
public partial class VisibilitySystem : Node2D
{
	[Export] public int ViewRange = 15;
	[Export] public float UpdateInterval = 0.1f;
	
	private Dictionary<int, Vector2> _playerPositions = new();
	private GridSystem _gridSystem;
	private Sprite2D _fogSprite;
	private Image _visibilityMap;
	private ImageTexture _visibilityTexture;
	private ShaderMaterial _fogMaterial;
	
	private const int TileSize = 32;
	private float _timeSinceUpdate = 0f;
	private Vector2I _mapMin;
	private Vector2I _mapMax;
	private readonly HashSet<string> _blockingMaterials = new() { "wall" };

	public override void _Ready()
	{
		_gridSystem = GetNode<GridSystem>("../GridSystem");

		_gridSystem.ScanCompleted += OnGridScanCompleted;
		if (_gridSystem.Grid?.Count > 0)
			OnGridScanCompleted(_gridSystem.Grid);
	}
	
	public void RefreshGrid()
	{
		if (_gridSystem != null)
			OnGridScanCompleted(_gridSystem.Grid);
	}

	private void OnGridScanCompleted(Godot.Collections.Dictionary<Vector2I, string> grid)
	{
		_mapMin = new Vector2I(int.MaxValue, int.MaxValue);
		_mapMax = new Vector2I(int.MinValue, int.MinValue);
		
		foreach (var cell in grid.Keys)
		{
			if (cell.X < _mapMin.X) _mapMin.X = cell.X;
			if (cell.Y < _mapMin.Y) _mapMin.Y = cell.Y;
			if (cell.X > _mapMax.X) _mapMax.X = cell.X;
			if (cell.Y > _mapMax.Y) _mapMax.Y = cell.Y;
		}
		
		int width = _mapMax.X - _mapMin.X + 1;
		int height = _mapMax.Y - _mapMin.Y + 1;
		
		_visibilityMap = Image.Create(width, height, false, Image.Format.Rf);
		_visibilityTexture = ImageTexture.CreateFromImage(_visibilityMap);
		
		var shader = GD.Load<Shader>("res://Assets/Shaders/FogTileShader.gdshader");
		_fogMaterial = new ShaderMaterial { Shader = shader };
		_fogMaterial.SetShaderParameter("visibility_map", _visibilityTexture);
		_fogMaterial.SetShaderParameter("tile_size", TileSize);
		
		var fogTexture = new PlaceholderTexture2D { Size = new Vector2I(width * TileSize, height * TileSize) };
		_fogSprite = new Sprite2D
		{
			Texture = fogTexture,
			Material = _fogMaterial,
			Position = new Vector2((_mapMin.X + _mapMax.X) * TileSize / 2 + TileSize / 2, (_mapMin.Y + _mapMax.Y) * TileSize / 2 + TileSize / 2)
		};
		
		AddChild(_fogSprite);
	}
	
	public override void _Process(double delta)
	{
		if (_fogSprite == null) return;
		
		_timeSinceUpdate += (float)delta;
		if (_timeSinceUpdate >= UpdateInterval)
		{
			UpdateVisibility();
			_timeSinceUpdate = 0f;
		}
	}
	
	public void ForceUpdate() => UpdateVisibility();

	public void AddPlayer(int playerId, Vector2 position) => _playerPositions[playerId] = position;
	public void UpdatePlayerPosition(int playerId, Vector2 position) => _playerPositions[playerId] = position;
	public void RemovePlayer(int playerId) => _playerPositions.Remove(playerId);
	
	private void UpdateVisibility()
	{
		if (_playerPositions.Count == 0) return;

		for (int y = 0; y < _visibilityMap.GetHeight(); y++)
		{
			for (int x = 0; x < _visibilityMap.GetWidth(); x++)
			{
				Vector2I cellPos = new(x + _mapMin.X, y + _mapMin.Y);
				float visibility = CalculateCellVisibility(cellPos);
				_visibilityMap.SetPixel(x, y, new Color(visibility, 0, 0, 1));
			}
		}
		
		_visibilityTexture.Update(_visibilityMap);
	}
	
	private float CalculateCellVisibility(Vector2I cellPos)
	{
		Vector2 cellWorldPos = new(cellPos.X * TileSize + TileSize / 2, cellPos.Y * TileSize + TileSize / 2);
		
		foreach (var playerPos in _playerPositions.Values)
		{
			float distance = cellWorldPos.DistanceTo(playerPos);
			float maxDistance = ViewRange * TileSize;
			
			if (distance <= maxDistance)
			{
				if (!HasWallBetween(playerPos, cellWorldPos))
				{
					float falloff = 1.0f - (distance / maxDistance);
					return Mathf.Clamp(falloff, 0, 1);
				}
			}
		}
		
		return 0f;
	}
	
	private bool HasWallBetween(Vector2 start, Vector2 end)
	{
		Vector2I startCell = new((int)(start.X / TileSize), (int)(start.Y / TileSize));
		Vector2I endCell = new((int)(end.X / TileSize), (int)(end.Y / TileSize));
		
		int x = startCell.X, y = startCell.Y;
		int dx = Mathf.Abs(endCell.X - x), dy = Mathf.Abs(endCell.Y - y);
		int sx = x < endCell.X ? 1 : -1, sy = y < endCell.Y ? 1 : -1;
		int err = dx - dy;
		
		while (x != endCell.X || y != endCell.Y)
		{
			Vector2I currentCell = new(x, y);
			if (currentCell != startCell && IsCellBlocking(currentCell))
				return true;
			
			int e2 = 2 * err;
			if (e2 > -dy) { err -= dy; x += sx; }
			if (e2 < dx) { err += dx; y += sy; }
		}
		
		return false;
	}
	
	private bool IsCellBlocking(Vector2I cell)
	{
		string type = _gridSystem?.GetTileTypeAtCell(cell);
		return !string.IsNullOrEmpty(type) && _blockingMaterials.Contains(type.ToLower());
	}
}