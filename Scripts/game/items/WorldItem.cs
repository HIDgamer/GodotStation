using Godot;
using System;

public partial class WorldItem : RigidBody2D
{
	[Export] public string ItemId;
	[Export] public int Quantity = 1;
	[Export] public Item ItemData;
	
	[Export] public int IconFrame = 0;
	[Export] public int InHandLeftFrame = 0;
	[Export] public int InHandRightFrame = 0;
	[Export] public int WornFrame = 0;
	
	private ItemSpriteSystem _spriteSystem;
	private GridSystem _gridSystem;
	private Vector2I _currentTile;
	private bool _isThrowing = false;
	private bool _hasBeenSynced = false;
	private bool _hasInitialPosition = false;
	private bool _spawnPrepared = false;
	private bool _isMouseOver = false;
	
	public override void _Ready()
	{
		AddToGroup("WorldItems");
	_spriteSystem = GetNodeOrNull<ItemSpriteSystem>("Icon");
		
		FreezeMode = FreezeModeEnum.Kinematic;
		Freeze = true;
		Visible = false;
		
		var collisionShape = GetNodeOrNull<CollisionShape2D>("CollisionShape2D");
		if (collisionShape == null)
		{
			collisionShape = new CollisionShape2D();
			collisionShape.Name = "CollisionShape2D";
			collisionShape.Shape = new RectangleShape2D() { Size = new Vector2(32, 32) };
			AddChild(collisionShape);
			GD.Print($"[WorldItem] Added default collision shape to {ItemData?.ItemName ?? "unknown item"}");
		}
		
		MouseEntered += () => _isMouseOver = true;
		MouseExited += () => _isMouseOver = false;
		
		if (Multiplayer.IsServer())
		{
			SetMultiplayerAuthority(1);
			_hasBeenSynced = true;
			if (!_spawnPrepared && !_hasInitialPosition)
				InitAtPosition(GlobalPosition);
		}
		else
		{
			_hasBeenSynced = true;
		}
		
		UpdateSpriteState();
	}
	
	public void HandleWorldItemClick()
	{
	}
	
	public void HandleWorldItemDoubleClick()
	{
		var mob = GetTree().GetFirstNodeInGroup("Player") as Mob;
		if (mob == null)
		{
			foreach (var node in GetTree().GetNodesInGroup("Mob"))
			{
				if (node is Mob candidate && candidate.IsMultiplayerAuthority())
				{
					mob = candidate;
					break;
				}
			}
		}

		if (mob != null)
		{
			TryPickup(mob);
		}
	}
	
	public void InitAtPosition(Vector2 position)
	{
		GlobalPosition = position;
		_hasInitialPosition = true;
		Visible = true;
		if (Multiplayer.IsServer())
		{
			Rpc(nameof(SyncPositionRpc), position);
			CallDeferred(nameof(SnapToGrid));
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPositionRpc(Vector2 position)
	{
		GlobalPosition = position;
		_hasInitialPosition = true;
		Visible = true;
	}
	
	public void ResetForPool()
	{
		_gridSystem = null;
		_isThrowing = false;
		_hasInitialPosition = false;
		_spawnPrepared = false;
		Rotation = 0;
		Modulate = new Color(1, 1, 1, 1);
		Scale = Vector2.One;
	}

	public void PrepareSpawn(Vector2 position)
	{
		_spawnPrepared = true;
		GlobalPosition = position;
		Visible = true;
	}
	
	private void SnapToGrid()
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world != null)
		{
			_gridSystem = world.GetNodeOrNull<GridSystem>("GridSystem");
			
			if (_gridSystem != null)
			{
				_currentTile = _gridSystem.WorldToGrid(GlobalPosition);
				GlobalPosition = _gridSystem.GridToWorld(_currentTile);
				_gridSystem.RegisterEntity(this, _currentTile);
			}
		}
	}
	
	public bool IsPixelAtPosition(Vector2 localPos) => localPos.Length() < 32;
	
	public bool TryPickup(Mob mob)
	{
		if (!Multiplayer.IsServer()) 
		{
			GD.Print($"[WorldItem] TryPickup called on client, requesting from server");
			RpcId(1, nameof(RequestPickupRpc), mob.GetMultiplayerAuthority());
			return false;
		}
		
		var inventory = mob.GetNodeOrNull<Inventory>("Inventory");
		if (inventory == null) 
		{
			GD.PrintErr($"[WorldItem] No inventory found on mob");
			return false;
		}

		var activeSlot = inventory.GetActiveHand() == 0 ? "left_hand" : "right_hand";
		if (inventory.GetEquipped(activeSlot) != null)
			return false;
		
		if (ItemData == null)
		{
			GD.PrintErr($"[WorldItem] No ItemData");
			return false;
		}

		if (string.IsNullOrEmpty(ItemData.ScenePath) && !string.IsNullOrEmpty(SceneFilePath))
			ItemData.ScenePath = SceneFilePath;
		
		GD.Print($"[WorldItem] Server attempting pickup: {ItemData.ItemName} by {mob.Name}");
		
		if (inventory.AddItem(ItemData, Quantity))
		{
			PlayPickupAnimation(mob.GlobalPosition);
			Rpc(nameof(PlayPickupAnimationRpc), mob.GlobalPosition);
			return true;
		}
		
		GD.Print($"[WorldItem] Inventory.AddItem returned false");
		return false;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestPickupRpc(int ownerPeerId)
	{
		if (!Multiplayer.IsServer()) return;

		var senderId = Multiplayer.GetRemoteSenderId();
		if (senderId > 0 && ownerPeerId > 0 && senderId != ownerPeerId)
		{
			GD.PrintErr($"[WorldItem] Pickup sender mismatch: sender={senderId}, owner={ownerPeerId}");
			return;
		}

		var resolvedPeerId = senderId > 0 ? senderId : ownerPeerId;
		var mob = FindMobByAuthority(resolvedPeerId);
		if (mob == null)
		{
			GD.Print($"[WorldItem] Server couldn't find mob for pickup: peer={resolvedPeerId}");
			return;
		}

		TryPickup(mob);
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void PlayPickupAnimationRpc(Vector2 targetPos)
	{
		PlayPickupAnimation(targetPos);
	}
	
	public void ThrowToPosition(Vector2 targetPos)
	{
		if (Multiplayer.IsServer())
		{
			ThrowToPositionLocal(targetPos);
			Rpc(nameof(ThrowToPositionRpc), targetPos);
		}
		else
		{
			GD.Print($"[WorldItem] Client requesting throw to {targetPos}");
			RpcId(1, nameof(RequestThrowRpc), targetPos);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestThrowRpc(Vector2 targetPos)
	{
		if (!Multiplayer.IsServer()) return;
		
		GD.Print($"[WorldItem] Server received throw request to {targetPos}");
		ThrowToPositionLocal(targetPos);
		Rpc(nameof(ThrowToPositionRpc), targetPos);
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ThrowToPositionRpc(Vector2 targetPos)
	{
		ThrowToPositionLocal(targetPos);
		_hasInitialPosition = true;
		Visible = true;
	}
	
	private void ThrowToPositionLocal(Vector2 targetPos)
	{
		_isThrowing = true;
		
		if (_gridSystem == null)
		{
			var world = GetTree().GetFirstNodeInGroup("World");
			_gridSystem = world?.GetNodeOrNull<GridSystem>("GridSystem");
			
			if (_gridSystem != null)
			{
				_currentTile = _gridSystem.WorldToGrid(GlobalPosition);
				GD.Print($"[WorldItem] Initialized GridSystem, current tile: {_currentTile}, pos: {GlobalPosition}");
			}
			else
			{
				GD.PrintErr($"[WorldItem] Failed to get GridSystem from World");
			}
		}
		
		if (_gridSystem != null)
			_gridSystem.UnregisterEntity(this, _currentTile);
		
		var world2 = GetTree().GetFirstNodeInGroup("World");
		var collisionMgr = world2?.GetNodeOrNull<CollisionManager>("CollisionManager");
		
		var startTile = _gridSystem?.WorldToGrid(GlobalPosition) ?? Vector2I.Zero;
		var targetTile = _gridSystem?.WorldToGrid(targetPos) ?? Vector2I.Zero;
		GD.Print($"[WorldItem] Throw from {startTile} (pos {GlobalPosition}) to {targetTile} (pos {targetPos})");
		
		var finalTile = FindThrowLandingTile(startTile, targetTile, collisionMgr);
		var finalPos = _gridSystem?.GridToWorld(finalTile) ?? targetPos;
		GD.Print($"[WorldItem] Final position: {finalPos} (tile {finalTile})");
		
		var tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(this, "global_position", finalPos, 0.3f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(this, "rotation", Mathf.Pi * 4, 0.3f).SetTrans(Tween.TransitionType.Linear);
		tween.Chain().TweenCallback(Callable.From(() => {
			_isThrowing = false;
			Rotation = 0;
			if (_gridSystem != null)
			{
				_currentTile = finalTile;
				GlobalPosition = _gridSystem.GridToWorld(_currentTile);
				_gridSystem.RegisterEntity(this, _currentTile);
				GD.Print($"[WorldItem] Landed and snapped to: {GlobalPosition}");
			}
		}));
	}
	
	private Vector2I FindThrowLandingTile(Vector2I start, Vector2I target, CollisionManager collision)
	{
		if (collision == null) return target;
		
		var direction = (target - start);
		var steps = Mathf.Max(Mathf.Abs(direction.X), Mathf.Abs(direction.Y));
		if (steps == 0) return start;
		
		var stepX = direction.X / (float)steps;
		var stepY = direction.Y / (float)steps;
		var lastValid = start;
		
		for (int i = 1; i <= steps; i++)
		{
			var checkTile = new Vector2I(
				start.X + Mathf.RoundToInt(stepX * i),
				start.Y + Mathf.RoundToInt(stepY * i)
			);
			
			if (!collision.IsWalkable(checkTile, false))
			{
				GD.Print($"[WorldItem] Hit wall at {checkTile}, landing at {lastValid}");
				return lastValid;
			}

			var entities = collision.GetEntitiesAt(checkTile);
			foreach (var entity in entities)
			{
				if (entity is Mob mob && !mob.IsGhost)
				{
					GD.Print($"[WorldItem] Path blocked by mob at {checkTile}, landing on mob tile");
					return checkTile;
				}
			}
			
			lastValid = checkTile;
		}
		
		GD.Print($"[WorldItem] Clear path, landing at {lastValid}");
		return lastValid;
	}
	
	private void PlayPickupAnimation(Vector2 targetPos)
	{
		if (_gridSystem != null)
			_gridSystem.UnregisterEntity(this, _currentTile);
		
		var tween = CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(this, "global_position", targetPos, 0.2f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
		tween.TweenProperty(this, "modulate:a", 0.0f, 0.2f);
		tween.TweenProperty(this, "scale", Vector2.Zero, 0.2f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.In);
		tween.Chain().TweenCallback(Callable.From(() => {
			var poolMgr = GetTree().Root.GetNodeOrNull<ItemPoolManager>("ItemPoolManager");
			if (poolMgr != null)
				poolMgr.Return(this);
			else
				QueueFree();
		}));
	}
	
	public void ApplyFrameAndRegionSettings()
	{
		if (_spriteSystem == null) return;
		
		var iconSprite = _spriteSystem.GetIconSprite();
		if (iconSprite != null)
		{
			if (IconFrame >= 0)
			{
				int totalFrames = iconSprite.Hframes * iconSprite.Vframes;
				if (totalFrames > 1)
				{
					iconSprite.Frame = Mathf.Clamp(IconFrame, 0, totalFrames - 1);
				}
			}
		}
	}
	
	private void UpdateSpriteState()
	{
		if (_spriteSystem == null) return;
		ApplyFrameAndRegionSettings();
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void UpdateSpriteStateRpc()
	{
		UpdateSpriteState();
	}
	
	public bool Interact(Mob user, WorldItem heldItem = null)
	{
		return false;
	}

	private Mob FindMobByAuthority(int peerId)
	{
		if (peerId <= 0) return null;

		var world = GetTree().GetFirstNodeInGroup("World");
		var byName = world?.GetNodeOrNull<Mob>(peerId.ToString());
		if (byName != null)
			return byName;

		foreach (var node in GetTree().GetNodesInGroup("Mob"))
		{
			if (node is Mob mob && mob.GetMultiplayerAuthority() == peerId)
				return mob;
		}

		return null;
	}
}
