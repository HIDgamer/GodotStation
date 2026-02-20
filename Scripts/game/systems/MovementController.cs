using Godot;

public partial class MovementController : Node2D, IMobSystem
{
	[Export] public bool UseGridMovement = true;

	private Mob _mob;
	private GridSystem _grid;
	private CollisionManager _collision;
	private Node _sprites;
	private PlayerInteractionSystem _interactionSystem;
	
	private const int TileSize = 32;
	private const float GridMoveDuration = 0.2f;
	
	private Vector2? _targetPos;
	private Vector2 _startPos;
	private float _moveProgress;
	private int _facing;
	private int _lastFacing = -1;
	private string _lastState = "";
	private bool _lastPeeking;
	private Vector2I _currentTile;
	private bool _isMoving;
	private Vector2I? _queuedDir;
	private float _speedMod = 1.0f;
	private float _interactionSpeedMod = 1.0f;
	private bool _isPeeking;
	private Vector2 _lastMousePos = Vector2.Zero;
	private float _mouseSyncTimer;
	private float _transformSyncTimer;
	private bool _isCrawling;
	private DoAfterComponent _doAfter;
	private MobStateSystem _stateSystem;
	
	
	private const float MouseSyncInterval = 0.1f;
	private const float TransformSyncInterval = 0.05f;

	public void Init(Mob mob)
	{
		_mob = mob;
		_grid = mob.GetNodeOrNull<GridSystem>("../GridSystem");
		_collision = mob.GetNodeOrNull<CollisionManager>("../CollisionManager");
		_sprites = mob.GetNodeOrNull("SpriteSystem");
		_interactionSystem = mob.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		_doAfter = mob.GetNodeOrNull<DoAfterComponent>("DoAfterComponent");
		_stateSystem = mob.GetNodeOrNull<MobStateSystem>("MobStateSystem");

		if (mob.IsMultiplayerAuthority())
			mob.GetNode<Camera2D>("PlayerCameraSetup")?.MakeCurrent();

		if (UseGridMovement && _grid != null)
			SnapToGrid();

		_currentTile = GetTileCoords(mob.Position);
		_collision?.EntityEnteredTile(mob, _currentTile);
	}

	public void Process(double delta)
	{
		bool allowInput = !_mob.DisableMovement;

		if (UseGridMovement && _grid != null)
		{
			if (allowInput)
				ProcessGridInput();
			UpdateGridMovement(delta);
		}
		else
		{
			if (allowInput)
				ProcessFreeroamMovement(delta);
		}

		SyncTransform(delta);
		UpdateTileTracking();
		UpdateSprites();
	}
	
	private void SnapToGrid()
	{
		int tx = Mathf.RoundToInt(_mob.Position.X / TileSize);
		int ty = Mathf.RoundToInt(_mob.Position.Y / TileSize);
		_mob.Position = new Vector2(tx * TileSize + TileSize / 2f, ty * TileSize + TileSize / 2f);
	}
	
	private Vector2I GetTileCoords(Vector2 position)
	{
		return new Vector2I(
			(int)Mathf.Floor(position.X / TileSize),
			(int)Mathf.Floor(position.Y / TileSize)
		);
	}
	
	private void ProcessGridInput()
	{
		if (!_mob.IsMultiplayerAuthority() || IsUiTyping())
			return;

		_isPeeking = Input.IsActionPressed("peek");
		var dir = GetInputDirection();

		if (_isPeeking && dir != Vector2I.Zero)
		{
			_facing = DirectionFromVector(dir);
			return;
		}

		if (dir != Vector2I.Zero && !_targetPos.HasValue)
			TryStartMovement(dir);
		else if (dir != Vector2I.Zero)
			_queuedDir = dir;
		else
			_queuedDir = null;
	}
	
	private Vector2I GetInputDirection()
	{
		if (Input.IsActionPressed("right")) return Vector2I.Right;
		if (Input.IsActionPressed("left")) return Vector2I.Left;
		if (Input.IsActionPressed("up")) return Vector2I.Up;
		if (Input.IsActionPressed("down")) return Vector2I.Down;
		return Vector2I.Zero;
	}
	
	private int DirectionFromVector(Vector2I dir)
	{
		if (dir.Y > 0) return 0;
		if (dir.Y < 0) return 1;
		if (dir.X > 0) return 2;
		if (dir.X < 0) return 3;
		return _facing;
	}
	
	public void TryStartMovement(Vector2I dir)
	{
		if (_interactionSystem?.GetPulledBy() != null)
		{
			_interactionSystem.OnPulledMoveAttempt();
			return;
		}

		var currentTile = GetTileCoords(_mob.Position);
		var targetTile = currentTile + dir;
		
		bool tileWalkable = _mob.IsGhost || CanEnterTile(targetTile);
		
		if (tileWalkable && _collision != null)
		{
			var entities = _collision.GetEntitiesAt(targetTile);
			bool hasMob = false;
			
			foreach (var entity in entities)
			{
				if (entity is Mob otherMob && otherMob != _mob && !_mob.IsGhost)
				{
					hasMob = true;
					break;
				}
			}
			
			if (hasMob)
			{
				tileWalkable = _collision.HandleMobBump(_mob, targetTile);
			}
		}

		if (tileWalkable)
		{
			_facing = DirectionFromVector(dir);
			
			if (_stateSystem != null && _stateSystem.GetState() == MobState.Prone && !_isCrawling)
			{
				StartCrawl(dir, targetTile);
			}
			else if (!_isCrawling)
			{
				_targetPos = (Vector2)targetTile * TileSize + new Vector2(TileSize / 2f, TileSize / 2f);
				_startPos = _mob.Position;
				_moveProgress = 0f;
				_isMoving = true;
				_queuedDir = null;
				_interactionSystem?.OnOwnerMovementStarted(currentTile, targetTile);
			}
		}
	}

	public bool TryStartForcedMovement(Vector2I targetTile, bool ignoreEntities = false, bool allowRetarget = false)
	{
		var currentTile = GetTileCoords(_mob.Position);
		var dir = targetTile - currentTile;

		if (dir == Vector2I.Zero) return false;
		if (Mathf.Abs(dir.X) > 1 || Mathf.Abs(dir.Y) > 1) return false;

		if (_targetPos.HasValue)
		{
			if (!allowRetarget)
				return false;

			_facing = DirectionFromVector(dir);
			_targetPos = (Vector2)targetTile * TileSize + new Vector2(TileSize / 2f, TileSize / 2f);
			_startPos = _mob.Position;
			_moveProgress = 0f;
			_isMoving = true;
			_queuedDir = null;
			return true;
		}

		bool tileWalkable = _mob.IsGhost || CanEnterTile(targetTile);

		if (tileWalkable && _collision != null && !ignoreEntities)
		{
			var entities = _collision.GetEntitiesAt(targetTile);
			foreach (var entity in entities)
			{
				if (entity is Mob otherMob && otherMob != _mob && !_mob.IsGhost)
				{
					tileWalkable = _collision.HandleMobBump(_mob, targetTile);
					break;
				}
			}
		}

		if (!tileWalkable) return false;

		_facing = DirectionFromVector(dir);
		_targetPos = (Vector2)targetTile * TileSize + new Vector2(TileSize / 2f, TileSize / 2f);
		_startPos = _mob.Position;
		_moveProgress = 0f;
		_isMoving = true;
		_queuedDir = null;
		return true;
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	public void StartForcedMovementRpc(Vector2I targetTile, bool ignoreEntities, bool allowRetarget)
	{
		TryStartForcedMovement(targetTile, ignoreEntities, allowRetarget);
	}
	
	private void StartCrawl(Vector2I dir, Vector2I targetTile)
	{
		_isCrawling = true;
		
		float crawlTime = CalculateCrawlTime();
		var spriteSystem = _mob.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		spriteSystem?.PlayDoAfterAnimation(crawlTime);
		
		_doAfter?.StartAction(crawlTime,
			onComplete: () => {
				_targetPos = (Vector2)targetTile * TileSize + new Vector2(TileSize / 2f, TileSize / 2f);
				_startPos = _mob.Position;
				_moveProgress = 0f;
				_isMoving = true;
				_isCrawling = false;
				_queuedDir = null;
				_interactionSystem?.OnOwnerMovementStarted(GetTileCoords(_mob.Position), targetTile);
			},
			onCancel: () => {
				_isCrawling = false;
			}
		);
	}
	
	private float CalculateCrawlTime()
	{
		return 1.0f;
	}
	
	private bool CanEnterTile(Vector2I tile)
	{
		return _collision?.IsWalkable(tile) ?? true;
	}
	
	private void UpdateGridMovement(double delta)
	{
		if (!_targetPos.HasValue)
		{
			_isMoving = false;
			return;
		}

		float currentSpeedMod = GetCurrentSpeedMultiplier();
		_moveProgress += (float)delta * currentSpeedMod / GridMoveDuration;
		
		if (_moveProgress >= 1.0f)
		{
			_mob.Position = _targetPos.Value;
			_targetPos = null;
			_moveProgress = 0f;
			
			if (_queuedDir.HasValue)
				TryStartMovement(_queuedDir.Value);
			else
				_isMoving = false;
		}
		else
		{
			_mob.Position = _startPos.Lerp(_targetPos.Value, _moveProgress);
		}
	}
	
	private void ProcessFreeroamMovement(double delta)
	{
		if (!_mob.IsMultiplayerAuthority() || IsUiTyping())
			return;

		_isPeeking = Input.IsActionPressed("peek");
		var velocity = GetInputVelocity();

		if (_isPeeking && velocity != Vector2.Zero)
		{
			_facing = Mathf.Abs(velocity.X) > Mathf.Abs(velocity.Y) 
				? (velocity.X > 0 ? 2 : 3) 
				: (velocity.Y > 0 ? 0 : 1);
			return;
		}

		_isMoving = velocity.Length() > 0.1f;
		if (_isMoving)
		{
			_facing = Mathf.Abs(velocity.X) > Mathf.Abs(velocity.Y) 
				? (velocity.X > 0 ? 2 : 3) 
				: (velocity.Y > 0 ? 0 : 1);

			float currentSpeedMod = GetCurrentSpeedMultiplier();
			Vector2 intended = _mob.Position + velocity * (float)delta * 120f * currentSpeedMod;
			Vector2I tile = GetTileCoords(intended);
			
			if (_collision == null || (_mob.IsGhost ? _collision.IsTile(tile) : _collision.IsWalkable(tile)))
				_mob.Position = intended;
		}
	}
	
	private Vector2 GetInputVelocity()
	{
		Vector2 velocity = Vector2.Zero;
		if (Input.IsActionPressed("right")) velocity.X += 1;
		if (Input.IsActionPressed("left")) velocity.X -= 1;
		if (Input.IsActionPressed("up")) velocity.Y -= 1;
		if (Input.IsActionPressed("down")) velocity.Y += 1;
		return velocity.Length() > 0 ? velocity.Normalized() : velocity;
	}
	
	private void SyncTransform(double delta)
	{
		if (!_mob.IsMultiplayerAuthority()) return;
		
		_transformSyncTimer += (float)delta;
		if (_transformSyncTimer >= TransformSyncInterval)
		{
			BroadcastTransform();
			_transformSyncTimer = 0f;
		}
		
		if (_isPeeking)
		{
			_mouseSyncTimer += (float)delta;
			if (_mouseSyncTimer >= MouseSyncInterval)
			{
				var mousePos = GetGlobalMousePosition();
				if (_lastMousePos.DistanceTo(mousePos) > 5.0f)
				{
					_lastMousePos = mousePos;
					_sprites?.Call("SetMouseTarget", mousePos);
					BroadcastMouseTarget(mousePos);
				}
				_mouseSyncTimer = 0f;
			}
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncTransformRpc(int peerId, Vector2 position, float rotation)
	{
		if (_mob.GetMultiplayerAuthority() == peerId)
		{
			_mob.Position = position;
			_mob.Rotation = rotation;
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncDirectionRpc(int peerId, int direction)
	{
		if (_mob.GetMultiplayerAuthority() == peerId)
		{
			_facing = direction;
			_sprites?.Call("SetDirection", direction);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStateRpc(int peerId, string state)
	{
		if (_mob.GetMultiplayerAuthority() == peerId)
		{
			_sprites?.Call("SetState", state);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPeekingRpc(int peerId, bool peeking)
	{
		if (_mob.GetMultiplayerAuthority() == peerId)
		{
			_isPeeking = peeking;
			_sprites?.Call("SetPeeking", peeking);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncMouseTargetRpc(int peerId, Vector2 target)
	{
		if (_mob.GetMultiplayerAuthority() == peerId)
		{
			_sprites?.Call("SetMouseTarget", target);
		}
	}
	
	private void UpdateTileTracking()
	{
		if (_collision == null) return;

		var newTile = GetTileCoords(_mob.Position);
		if (newTile != _currentTile)
		{
			GD.Print($"[MovementController] {(_mob.GetPlayerName() ?? "Unknown")} tile change: {_currentTile} -> {newTile}");
			
			_collision.EntityExitedTile(_mob, _currentTile);
			_collision.EntityEnteredTile(_mob, newTile);
			
			_currentTile = newTile;
		}
	}
	
	private void UpdateSprites()
	{
		if (_sprites == null) return;
		
		string state = _isMoving ? "walking" : "idle";
		
		if (_mob.IsMultiplayerAuthority())
		{
			_sprites.Call("SetDirection", _facing);
			_sprites.Call("SetState", state);
			_sprites.Call("SetPeeking", _isPeeking);
			
			if (_facing != _lastFacing)
			{
				BroadcastDirection(_facing);
				_lastFacing = _facing;
			}
			if (state != _lastState)
			{
				BroadcastState(state);
				_lastState = state;
			}
			if (_isPeeking != _lastPeeking)
			{
				BroadcastPeeking(_isPeeking);
				_lastPeeking = _isPeeking;
			}
		}
		else
		{
			_sprites.Call("SetDirection", _facing);
			_sprites.Call("SetState", state);
			_sprites.Call("SetPeeking", _isPeeking);
		}
	}
	public void SetNetworkFacing(int direction)
	{
		_facing = direction;
		_lastFacing = direction;
	}
	public void SetNetworkState(string state)
	{
		_isMoving = (state == "walking");
		_lastState = state;
	}
	public void SetNetworkPeeking(bool peeking)
	{
		_isPeeking = peeking;
		_lastPeeking = peeking;
	}
	
	private void BroadcastTransform()
	{
		GetNodeOrNull("/root/NetworkManager")?.Call("SyncTransform", _mob.GetMultiplayerAuthority(), _mob.Position, _mob.Rotation);
	}
	
	private void BroadcastDirection(int direction)
	{
		GetNodeOrNull("/root/NetworkManager")?.Call("SyncDirection", _mob.GetMultiplayerAuthority(), direction);
	}
	
	private void BroadcastState(string state)
	{
		GetNodeOrNull("/root/NetworkManager")?.Call("SyncState", _mob.GetMultiplayerAuthority(), state);
	}
	
	private void BroadcastPeeking(bool peeking)
	{
		GetNodeOrNull("/root/NetworkManager")?.Call("SyncPeeking", _mob.GetMultiplayerAuthority(), peeking);
	}
	
	private void BroadcastMouseTarget(Vector2 target)
	{
		GetNodeOrNull("/root/NetworkManager")?.Call("SyncMouseTarget", _mob.GetMultiplayerAuthority(), target);
	}

	public void SetSpeedMultiplier(float multiplier) => _speedMod = Mathf.Max(0.0f, multiplier);
	public float GetSpeedMultiplier() => _speedMod;
	public void SetInteractionSpeedMultiplier(float multiplier) => _interactionSpeedMod = Mathf.Max(0.0f, multiplier);
	public bool IsMoving() => _isMoving || _targetPos.HasValue;
	
	
	private float GetCurrentSpeedMultiplier()
	{
		// NOTE: _speedMod already contains the prone penalty (0.5f) because.
		// MobStateSystem.ApplySpeedModifier calls SetSpeedMultiplier(0.5f) when.
		// entering Prone state. Do NOT multiply by 0.5 again here or the target.
		// will crawl at 25% speed instead of 50%, making the puller pull away and.
		// immediately triggering CheckForGripLoss.
		var stateSystem = _mob.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (stateSystem != null && stateSystem.GetState() == MobState.Prone)
		{
			var interactionSystem = _mob.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
			if (interactionSystem?.IsPulling() == true)
			{
				// Puller is prone while carrying (e.g. fireman carry while prone) -.
				// apply the heavier carry penalty on top of the base speed.
				var skillSystem = _mob.GetNodeOrNull<SkillComponent>("SkillComponent");
				return _speedMod * 0.3f * CalculateCarrySpeedMultiplier(skillSystem);
			}
		}

		return _speedMod * _interactionSpeedMod;
	}

	private bool IsUiTyping()
	{
		var gameManager = GetNodeOrNull("/root/GameManager") as GameManager;
		if (gameManager != null && gameManager.ChatInputActive)
			return true;

		foreach (var node in GetTree().GetNodesInGroup("TextInput"))
		{
			if (node is Window window && window.Visible)
			{
				var focused = window.GetViewport()?.GuiGetFocusOwner();
				if (focused is LineEdit)
					return true;
			}
		}

		var localFocus = GetViewport().GuiGetFocusOwner();
		if (localFocus is LineEdit)
			return true;
		
		var rootFocus = GetTree().Root?.GuiGetFocusOwner();
		return rootFocus is LineEdit;
	}
	
	private float CalculateCarrySpeedMultiplier(SkillComponent skillSystem)
	{
		if (skillSystem == null) return 0.5f;
		
		int skillLevel = skillSystem.GetSkillLevel(SkillType.FiremanCarry);
		
		float baseSpeed = 0.5f;
		float modifier = skillLevel * 0.1f;
		
		return Mathf.Clamp(baseSpeed + modifier, 0.5f, 1.0f);
	}

	public void FacePosition(Vector2 targetPos)
	{
		var dx = targetPos.X - _mob.Position.X;
		var dy = targetPos.Y - _mob.Position.Y;
		
		if (Mathf.Abs(dx) < 1 && Mathf.Abs(dy) < 1) return;
		
		_facing = Mathf.Abs(dx) > Mathf.Abs(dy) 
			? (dx > 0 ? 2 : 3) 
			: (dy > 0 ? 0 : 1);
		
		UpdateSprites();
	}
	
	public void Cleanup() { }
	
	public void ConfirmGridMovement(Vector2I targetTile)
	{
		if (_grid == null) return;
		
		var oldTile = _currentTile;
		var targetPos = _grid.GridToWorld(targetTile);
		_mob.Position = targetPos;
		_currentTile = targetTile;
		_collision?.UpdateEntityPosition(_mob, oldTile, targetTile);
		
		GD.Print($"[MovementController] Grid confirmation: {(_mob.GetPlayerName() ?? "Unknown")} snapped to tile {targetTile}");
	}
}
