using Godot;
using System.Collections.Generic;

/// <summary>
/// Ballistic projectile with grid-based movement and collision detection
/// </summary>
public partial class BallisticProjectile : Node2D
{
	[Export] public float Speed = 900.0f;
	[Export] public float Gravity = 0.0f;
	[Export] public bool StopOnWall = true;
	[Export] public bool StopOnMob = true;
	[Export] public bool StopOnGround = false;
	
	private Vector2 _start;
	private Vector2 _end;
	private Vector2 _direction;
	private float _travelTime;
	private float _elapsed;
	private float _gravityAccumulator;
	
	private GridSystem _gridSystem;
	private CollisionManager _collisionManager;
	private List<Vector2I> _pathTiles;
	private int _currentTileIndex;
	
	/// <summary>
	/// Initialize projectile with start and end positions
	/// </summary>
	public void Init(Vector2 start, Vector2 end, float speed)
	{
		_start = start;
		_end = end;
		Speed = speed;
		GlobalPosition = start;
		
		_direction = (end - start).Normalized();
		float dist = start.DistanceTo(end);
		_travelTime = Speed > 0f ? dist / Speed : 0.05f;
		_travelTime = Mathf.Clamp(_travelTime, 0.03f, 0.35f);
		
		// Calculate rotation for 360-degree aiming
		Rotation = _direction.Angle();
		
		// Build grid path for accuracy
		BuildGridPath();
		
		// Find grid system and collision manager
		FindSystems();
	}
	
	private void BuildGridPath()
	{
		_pathTiles = new List<Vector2I>();
		var start = _gridSystem?.WorldToGrid(_start) ?? Vector2I.Zero;
		var end = _gridSystem?.WorldToGrid(_end) ?? Vector2I.Zero;
		
		if (_gridSystem != null)
		{
			foreach (var tile in GridLine(start, end))
			{
				_pathTiles.Add(tile);
			}
		}
		
		_currentTileIndex = 0;
	}
	
	private static IEnumerable<Vector2I> GridLine(Vector2I start, Vector2I end)
	{
		int x0 = start.X;
		int y0 = start.Y;
		int x1 = end.X;
		int y1 = end.Y;
		
		int dx = Mathf.Abs(x1 - x0);
		int dy = Mathf.Abs(y1 - y0);
		int sx = x0 < x1 ? 1 : -1;
		int sy = y0 < y1 ? 1 : -1;
		int err = dx - dy;
		
		while (true)
		{
			yield return new Vector2I(x0, y0);
			if (x0 == x1 && y0 == y1) break;
			int e2 = 2 * err;
			if (e2 > -dy)
			{
				err -= dy;
				x0 += sx;
			}
			if (e2 < dx)
			{
				err += dx;
				y0 += sy;
			}
		}
	}
	
	private void FindSystems()
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world != null)
		{
			_gridSystem = world.GetNodeOrNull<GridSystem>("GridSystem");
			_collisionManager = world.GetNodeOrNull<CollisionManager>("CollisionManager");
		}
	}
	
	public override void _Process(double delta)
	{
		if (_travelTime <= 0f)
		{
			GlobalPosition = _end;
			QueueFree();
			return;
		}
		
		_elapsed += (float)delta;
		float t = Mathf.Clamp(_elapsed / _travelTime, 0f, 1f);
		
		// Apply gravity if enabled
		if (Gravity > 0f)
		{
			_gravityAccumulator += Gravity * (float)delta;
			Vector2 gravityOffset = new Vector2(0, _gravityAccumulator * (float)delta);
			_direction += gravityOffset;
			_direction = _direction.Normalized();
		}
		
		// Move along the path
		Vector2 nextPos = _start + _direction * (t * _start.DistanceTo(_end));
		GlobalPosition = nextPos;
		
		// Check for collisions along the grid path
		CheckGridCollisions();
		
		if (t >= 1f)
			QueueFree();
	}
	
	private void CheckGridCollisions()
	{
		if (_gridSystem == null || _collisionManager == null) return;
		
		var currentTile = _gridSystem.WorldToGrid(GlobalPosition);
		
		// Check if we've moved to a new tile
		if (_currentTileIndex < _pathTiles.Count && currentTile == _pathTiles[_currentTileIndex])
		{
			_currentTileIndex++;
		}
		
		// Check for wall collision
		if (StopOnWall && !_collisionManager.IsWalkable(currentTile, false))
		{
			QueueFree();
			return;
		}
		
		// Check for mob collision
		if (StopOnMob)
		{
			var entities = _collisionManager.GetEntitiesAt(currentTile);
			foreach (var entity in entities)
			{
				if (entity is Mob mob && mob != GetParent<Mob>())
				{
					// Hit mob - trigger damage
					TriggerMobHit(mob);
					QueueFree();
					return;
				}
			}
		}
		
		// Check for ground collision (if projectile hits floor)
		if (StopOnGround && _currentTileIndex >= _pathTiles.Count)
		{
			QueueFree();
			return;
		}
	}
	
	private void TriggerMobHit(Mob mob)
	{
		// Send RPC to server for damage calculation
		if (Multiplayer.IsServer())
		{
			mob.GetNodeOrNull<HealthSystem>("HealthSystem")
				?.ApplyDamage(DamageType.Brute, 10, "Projectile", null);
		}
		else
		{
			RpcId(1, nameof(RpcApplyDamage), mob.GetPath());
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RpcApplyDamage(NodePath mobPath)
	{
		var mob = GetNodeOrNull<Mob>(mobPath);
		if (mob != null)
		{
			mob.GetNodeOrNull<HealthSystem>("HealthSystem")
				?.ApplyDamage(DamageType.Brute, 10, "Projectile", null);
		}
	}
}