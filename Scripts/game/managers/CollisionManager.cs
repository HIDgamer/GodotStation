using Godot;
using System.Collections.Generic;

public partial class CollisionManager : Node
{
	private GridSystem _grid;
	private Dictionary<Vector2I, List<Node2D>> _entities = new();
	
	private HashSet<Mob> _processingCollisions = new();
	
	public override void _Ready()
	{
		_grid = GetParent().GetNodeOrNull<GridSystem>("GridSystem");
		
		var timer = new Timer();
		timer.Name = "CleanupTimer";
		timer.WaitTime = 5.0f;
		timer.Timeout += CleanupStaleReferences;
		timer.Autostart = true;
		timer.OneShot = false;
		AddChild(timer);
	}
	
	public void UpdateWalkable(Vector2I cell, string tileType)
	{
	}
	
	public bool IsWalkable(Vector2I cell, bool checkEntities = false)
	{
		if (_grid == null) return true;
		
		var tileType = _grid.GetTileTypeAtCell(cell);
		if (tileType == null) return false;
		if (tileType == "wall" || tileType == "window") return false;
		
		if (checkEntities)
		{
			var entities = GetEntitiesAt(cell);
			foreach (var entity in entities)
			{
				if (entity is Mob mob && !mob.IsGhost)
					return false;
			}
		}
		
		return true;
	}
	
	public bool IsTile(Vector2I cell)
	{
		return _grid?.GetTileTypeAtCell(cell) != null;
	}
	
	public bool HasBorderBlocker(Vector2I cell, Vector2I direction)
	{
		var tileType = _grid?.GetTileTypeAtCell(cell);
		if (tileType == "wall" || tileType == "window")
			return true;
		
		var checkCell = cell + direction;
		var checkType = _grid?.GetTileTypeAtCell(checkCell);
		return checkType == "wall" || checkType == "window";
	}
	
	public void EntityEnteredTile(Node2D entity, Vector2I cell)
	{
		if (!_entities.ContainsKey(cell))
			_entities[cell] = new List<Node2D>();
		if (!_entities[cell].Contains(entity))
			_entities[cell].Add(entity);
	}
	
	public void EntityExitedTile(Node2D entity, Vector2I cell)
	{
		if (_entities.TryGetValue(cell, out var list))
			list.Remove(entity);
	}
	
	public void UpdateEntityPosition(Node2D entity, Vector2I oldCell, Vector2I newCell)
	{
		if (oldCell != newCell)
		{
			if (entity is Mob mob)
			{
				GD.Print($"[CollisionManager] {mob.GetPlayerName()} entity tracking update: {oldCell} -> {newCell}");
			}
			EntityExitedTile(entity, oldCell);
			EntityEnteredTile(entity, newCell);
		}
	}
	
	public List<Node2D> GetEntitiesAt(Vector2I cell)
	{
		return _entities.TryGetValue(cell, out var list) ? list : new List<Node2D>();
	}
	
	public bool HandleMobBump(Mob bumper, Vector2I targetTile)
	{
		if (_processingCollisions.Contains(bumper))
		{
			GD.Print($"[CollisionManager] Collision already being processed for {bumper.GetPlayerName()}, skipping");
			return false;
		}
		
		
		GD.Print($"[CollisionManager] Mob bump attempt: {bumper.GetPlayerName()} -> target tile {targetTile}");
		
		_processingCollisions.Add(bumper);
		
		try
		{
			var entities = GetEntitiesAt(targetTile);
			foreach (var entity in entities)
			{
				if (entity is Mob target && target != bumper)
				{
					if (IsPullFollowMove(bumper, target))
					{
						return true;
					}

					var intentSystem = bumper.GetNodeOrNull<IntentSystem>("IntentSystem");
					var intent = intentSystem?.GetIntent() ?? Intent.Help;
					
					GD.Print($"[CollisionManager] Intent-based collision: {bumper.GetPlayerName()} ({intent}) vs {target.GetPlayerName()}");
					
					return HandleIntentCollision(bumper, target, intent, targetTile);
				}
			}
			
			var tileType = _grid?.GetTileTypeAtCell(targetTile);
			if (tileType == "wall")
			{
				GD.Print($"[CollisionManager] Wall collision blocked: {bumper.GetPlayerName()} -> wall at {targetTile}");
				return false;
			}
			
			GD.Print($"[CollisionManager] Free movement allowed: {bumper.GetPlayerName()} -> {targetTile}");
			return true;
		}
		finally
		{
			_processingCollisions.Remove(bumper);
		}
	}
	
	public bool HandleIntentCollision(Mob actor, Mob target, Intent intent, Vector2I targetTile)
	{
		switch (intent)
		{
			case Intent.Help:
				return HandleHelpCollision(actor, target, targetTile);
			case Intent.Disarm:
				return HandleDisarmCollision(actor, target, targetTile);
			case Intent.Grab:
				return HandleGrabCollision(actor, target, targetTile);
			case Intent.Harm:
				return HandleHarmCollision(actor, target, targetTile);
			default:
				return false;
		}
	}
	
	private bool HandleHelpCollision(Mob actor, Mob target, Vector2I targetTile)
	{
		if (actor == null || target == null || _grid == null)
			return false;
		if (actor == target)
			return false;

		var actorTile = GetTileCoords(actor.Position);
		var targetActorTile = GetTileCoords(target.Position);

		var targetToActor = actorTile - targetActorTile;
		var actorToTarget = targetActorTile - actorTile;
		return HandleMovement(actor, target, targetToActor, "help-swap", true)
			&& HandleMovement(target, actor, actorToTarget, "help-swap", true);
	}

	private bool HandleDisarmCollision(Mob actor, Mob target, Vector2I targetTile)
	{
		if (IsMobCurrentlyMoving(target))
		{
			GD.Print($"[CollisionManager] Disarm collision blocked because {target.GetPlayerName()} is already moving");
			return false;
		}

		var actorTile = GetTileCoords(actor.Position);
		var direction = targetTile - actorTile;
		var pushTile = targetTile + direction;
		
		if (IsWalkable(pushTile))
		{
			return HandleMovement(actor, target, direction, "disarm");
		}
		return false;
	}

	private bool IsMobCurrentlyMoving(Mob mob)
	{
		if (mob == null)
			return false;

		var movement = mob.GetNodeOrNull<MovementController>("MovementController");
		return movement?.IsMoving() ?? false;
	}
	
	private bool HandleGrabCollision(Mob actor, Mob target, Vector2I targetTile)
	{
		return HandleHelpCollision(actor, target, targetTile);
	}
	
	private bool HandleHarmCollision(Mob actor, Mob target, Vector2I targetTile)
	{
		return HandleHelpCollision(actor, target, targetTile);
	}
	
	
	private Vector2I GetTileCoords(Vector2 position)
	{
		return new Vector2I(
			(int)Mathf.Floor(position.X / 32),
			(int)Mathf.Floor(position.Y / 32)
		);
	}
	
	public void CleanupStaleReferences()
	{
		var validCollisions = new HashSet<Mob>();
		foreach (var mob in _processingCollisions)
		{
			if (IsInstanceValid(mob))
				validCollisions.Add(mob);
		}
		_processingCollisions = validCollisions;
	}
	
	private bool HandleMovement(Mob actor, Mob target, Vector2I direction, string interactionType, bool ignoreEntities = false)
	{
		if (actor == null || target == null || _grid == null)
			return false;
		if (actor == target)
			return false;
		
		var targetTile = GetTileCoords(target.Position);
		var targetTileAfterMove = targetTile + direction;
		
		if (!IsWalkable(targetTileAfterMove))
			return false;
		
		var targetMovement = target.GetNodeOrNull<MovementController>("MovementController");
		if (targetMovement == null)
			return false;
		
		if (!StartMovementSynced(target, targetTileAfterMove, ignoreEntities))
			return false;
		
		GD.Print($"[CollisionManager] {interactionType} movement started: {target.GetPlayerName()} -> direction {direction}");
		
		return true;
	}
	
	private bool StartMovementSynced(Mob target, Vector2I targetTile, bool ignoreEntities)
	{
		var targetMovement = target.GetNodeOrNull<MovementController>("MovementController");
		if (targetMovement == null)
			return false;

		if (!targetMovement.TryStartForcedMovement(targetTile, ignoreEntities, false))
			return false;

		targetMovement.Rpc(nameof(MovementController.StartForcedMovementRpc), targetTile, ignoreEntities, false);
		return true;
	}

	private bool IsPullFollowMove(Mob bumper, Mob target)
	{
		var bumperInteraction = bumper.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		var targetInteraction = target.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		return bumperInteraction?.GetPulling() == target || targetInteraction?.GetPulledBy() == bumper;
	}
	
}
