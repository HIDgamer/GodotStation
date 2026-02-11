using Godot;
using System.Collections.Generic;
using System.Threading.Tasks;

[GlobalClass]
public partial class VisibilitySystem : Node2D
{
	[Export] public int ViewRange = 20;
	[Export] public float FogIntensity = 0.3f;
	[Export] public float FogSpeed = 0.5f;
	
	private GridSystem _gridSystem;
	private ColorRect _fogRect;
	private ShaderMaterial _fogMaterial;
	private ImageTexture _wallImageTexture;
	private Vector2I _mapMin;
	private readonly HashSet<string> _blockingMaterials = new() { "wall" };
	private const int TileSize = 32;
	private const int TextureScale = 4;
	private Mob _cachedPlayer;
	private bool _isProcessingGrid;

	public override void _Ready()
	{
		_gridSystem = GetNodeOrNull<GridSystem>("../GridSystem");
		if (_gridSystem != null)
		{
			_gridSystem.ScanCompleted += OnGridScanCompleted;
			
			// Process existing grid if available
			if (_gridSystem.Grid?.Count > 0)
				OnGridScanCompleted(_gridSystem.Grid);
		}
	}

	public void RefreshGrid()
	{
		if (_gridSystem?.Grid != null && !_isProcessingGrid)
		{
			ProcessGridAsync(_gridSystem.Grid);
		}
	}

	private void OnGridScanCompleted(Godot.Collections.Dictionary<Vector2I, string> grid)
	{
		if (grid.Count == 0 || _isProcessingGrid) return;
		ProcessGridAsync(grid);
	}

	// Simplified async processing - no manual thread management needed
	private async void ProcessGridAsync(Godot.Collections.Dictionary<Vector2I, string> grid)
	{
		if (_isProcessingGrid) return;
		_isProcessingGrid = true;

		try
		{
			// Process grid on background thread
			var result = await Task.Run(() => ProcessGrid(grid));
			
			// Apply result on main thread
			if (IsInstanceValid(this))
			{
				ApplyGridResult(result.mapMin, result.width, result.height, result.wallTexture);
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"Error processing grid: {e.Message}");
		}
		finally
		{
			_isProcessingGrid = false;
		}
	}

	private (Vector2I mapMin, int width, int height, Image wallTexture) ProcessGrid(
		Godot.Collections.Dictionary<Vector2I, string> grid)
	{
		// Calculate map bounds
		var mapMin = new Vector2I(int.MaxValue, int.MaxValue);
		var mapMax = new Vector2I(int.MinValue, int.MinValue);
		
		foreach (var cell in grid.Keys)
		{
			mapMin.X = Mathf.Min(mapMin.X, cell.X);
			mapMin.Y = Mathf.Min(mapMin.Y, cell.Y);
			mapMax.X = Mathf.Max(mapMax.X, cell.X);
			mapMax.Y = Mathf.Max(mapMax.Y, cell.Y);
		}

		int width = mapMax.X - mapMin.X + 1;
		int height = mapMax.Y - mapMin.Y + 1;

		// Extract wall positions
		var wallData = new List<Vector2I>(grid.Count / 4);
		foreach (var kvp in grid)
		{
			if (_blockingMaterials.Contains(kvp.Value.ToLower()))
				wallData.Add(kvp.Key);
		}

		// Generate wall texture
		var wallTexture = GenerateWallTexture(wallData, mapMin, width, height, TextureScale);
		return (mapMin, width, height, wallTexture);
	}

	private void ApplyGridResult(Vector2I mapMin, int width, int height, Image wallTexture)
	{
		_mapMin = mapMin;
		
		// Update or create wall texture
		if (_wallImageTexture != null)
		{
			_wallImageTexture.Update(wallTexture);
		}
		else
		{
			_wallImageTexture = ImageTexture.CreateFromImage(wallTexture);
		}

		// Initialize fog material and rect if needed
		if (_fogMaterial == null)
		{
			InitializeFogSystem(width, height);
		}
		
		// Update shader parameters
		_fogMaterial.SetShaderParameter("wall_texture", _wallImageTexture);
		_fogMaterial.SetShaderParameter("map_min", _mapMin);
		_fogMaterial.SetShaderParameter("map_size", new Vector2I(width * TextureScale, height * TextureScale));
		_fogMaterial.SetShaderParameter("map_offset", new Vector2(_mapMin.X * TileSize, _mapMin.Y * TileSize));
	}

	private void InitializeFogSystem(int width, int height)
	{
		// Clean up old rect if exists
		if (_fogRect != null)
			_fogRect.QueueFree();

		// Load shader
		var shader = GD.Load<Shader>("uid://uyl8otyabpn6");
		_fogMaterial = new ShaderMaterial { Shader = shader };
		
		// Set shader parameters
		_fogMaterial.SetShaderParameter("view_range", ViewRange);
		_fogMaterial.SetShaderParameter("tile_scale", TextureScale);
		_fogMaterial.SetShaderParameter("fog_intensity", FogIntensity);
		_fogMaterial.SetShaderParameter("fog_speed", FogSpeed);

		// Create fog rect overlay
		_fogRect = new ColorRect
		{
			Material = _fogMaterial,
			MouseFilter = Control.MouseFilterEnum.Ignore,
			Position = new Vector2(_mapMin.X * TileSize, _mapMin.Y * TileSize),
			Size = new Vector2(width * TileSize, height * TileSize)
		};
		AddChild(_fogRect);
	}

	private static Image GenerateWallTexture(List<Vector2I> wallData, Vector2I mapMin, 
		int width, int height, int scale)
	{
		var texture = Image.CreateEmpty(width * scale, height * scale, false, Image.Format.R8);
		texture.Fill(Colors.Black);

		// Mark wall pixels
		foreach (var cell in wallData)
		{
			int baseX = (cell.X - mapMin.X) * scale;
			int baseY = (cell.Y - mapMin.Y) * scale;

			for (int dy = 0; dy < scale; dy++)
			{
				for (int dx = 0; dx < scale; dx++)
				{
					texture.SetPixel(baseX + dx, baseY + dy, new Color(1.0f, 0, 0, 1));
				}
			}
		}

		return texture;
	}

	public override void _Process(double delta)
	{
		if (_fogMaterial == null) return;

		// Cache player reference
		if (_cachedPlayer == null || !IsInstanceValid(_cachedPlayer))
		{
			_cachedPlayer = FindPlayerMob();
		}

		// Update player position in shader
		if (_cachedPlayer != null)
		{
			_fogMaterial.SetShaderParameter("player_position", _cachedPlayer.GlobalPosition);
		}
	}

	private Mob FindPlayerMob()
	{
		foreach (var node in GetTree().GetNodesInGroup("Mob"))
		{
			if (node is Mob mob && mob.IsMultiplayerAuthority())
			{
				return mob;
			}
		}
		return null;
	}
}