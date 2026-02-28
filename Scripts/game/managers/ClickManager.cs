using Godot;

public partial class ClickManager : Node2D
{
	private float _nextClick;
	private const float ClickCooldown = 0.1f;
	
	private Mob _mob;
	private MovementController _movementController;
	private SpriteSystem _spriteSystem;
	private PlayerInteractionSystem _interactionSystem;
	private IntentSystem _intentSystem;
	private GridSystem _gridSystem;

	public override void _Ready()
	{
		GD.Print("[ClickManager] _Ready called");
		_mob = GetParent<Mob>();
		_movementController = _mob.GetNodeOrNull<MovementController>("MovementController");
		_spriteSystem = _mob.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		_interactionSystem = _mob.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		_intentSystem = _mob.GetNodeOrNull<IntentSystem>("IntentSystem");
		_gridSystem = FindGridSystem();
		SetProcessUnhandledInput(true);
		GD.Print($"[ClickManager] Initialized - Mob: {_mob != null}, Movement: {_movementController != null}, Interaction: {_interactionSystem != null}, Intent: {_intentSystem != null}, Grid: {_gridSystem != null}");
	}
	
	public override void _Process(double delta)
	{
		if (_worldItemInteractionState == MouseInteractionState.Pressed)
		{
			_mouseDownTime += (float)delta;
			
			if (_mouseDownTime > DragTimeThreshold && _mouseDownItem != null)
			{
				_worldItemInteractionState = MouseInteractionState.Dragging;
			}
		}
	}
	
	private GridSystem FindGridSystem()
	{
		Node current = this;
		while (current != null)
		{
			var grid = current.GetNodeOrNull<GridSystem>("GridSystem");
			if (grid != null)
				return grid;
			current = current.GetParent();
		}
		return null;
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (_mob == null || !_mob.IsMultiplayerAuthority())
		{
			return;
		}
		
		var stateSystem = _mob.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (stateSystem != null && stateSystem.GetState() != MobState.Standing)
			return;
		
		if (@event is InputEventMouseMotion mouseMotion)
		{
			_spriteSystem?.SetMouseTarget(GetGlobalMousePosition());
			
			if (_isDragging && _dragTarget != null)
			{
				HandleDragUpdate();
			}
			
			if (_worldItemInteractionState == MouseInteractionState.Pressed && _mouseDownItem != null)
			{
				var currentPos = GetGlobalMousePosition();
				var dragDistance = _mouseDownPos.DistanceTo(currentPos);
				
				if (dragDistance > DragDistanceThreshold)
				{
					_worldItemInteractionState = MouseInteractionState.Dragging;
				}
			}
			return;
		}
		
		if (@event is InputEventMouseButton mouseEvent)
		{
			if (mouseEvent.Pressed && mouseEvent.ButtonIndex == MouseButton.Left)
			{
				HandleMousePressed(mouseEvent);
			}
			else if (!mouseEvent.Pressed && mouseEvent.ButtonIndex == MouseButton.Left)
			{
				HandleMouseReleased(mouseEvent);
			}
		}
	}
	
	private void HandleMousePressed(InputEventMouseButton mouseEvent)
	{
		var clickPos = GetGlobalMousePosition();
		var mods = GatherModifiers();
		
		_mouseDownPos = clickPos;
		_mouseDownTime = 0f;
		
		var interactionComponent = _mob.GetNodeOrNull<InteractionComponent>("InteractionComponent");
		bool isThrowMode = interactionComponent != null && (interactionComponent.IsThrowMode() || interactionComponent.IsLongThrowMode());
		
		if (isThrowMode)
		{
			return;
		}
		
		if (!mods.Ctrl)
		{
			var space = GetWorld2D().DirectSpaceState;
			var query = new PhysicsPointQueryParameters2D();
			query.Position = clickPos;
			var result = space.IntersectPoint(query);
			
			GD.Print($"[ClickManager] HandleMousePressed at {clickPos}, found {result.Count} colliders");
			
			WorldItem clickedItem = null;
			foreach (var hit in result)
			{
				var hitVar = (Godot.Variant)hit;
				if (hitVar.VariantType == Godot.Variant.Type.Dictionary)
				{
					var dict = (Godot.Collections.Dictionary)hitVar;
					if (dict.ContainsKey("collider"))
					{
						var collider = dict["collider"];
						GD.Print($"[ClickManager] Found collider: {collider}");
						if (collider.Obj is WorldItem item)
						{
							GD.Print($"[ClickManager] Found WorldItem: {item.ItemData?.ItemName ?? "unknown"}");
							clickedItem = item;
							break;
						}
					}
				}
			}
			
			if (clickedItem != null)
			{
				GD.Print($"[ClickManager] Setting _mouseDownItem to {clickedItem.ItemData?.ItemName}, state = PRESSED");
				_mouseDownItem = clickedItem;
				_worldItemInteractionState = MouseInteractionState.Pressed;
				return;
			}
		}
		
		GD.Print($"[ClickManager] No WorldItem clicked, continuing to mob/tile handling");
		
		if (_gridSystem != null)
		{
			var targetTile = _gridSystem.WorldToGrid(clickPos);
			var entities = _gridSystem.GetEntitiesOnTile(targetTile);
			
			Mob targetMob = null;
			foreach (var entity in entities)
			{
				if (entity is Mob mob && mob != _mob)
				{
					targetMob = mob;
					break;
				}
			}
			
			if (targetMob != null)
			{
				if (!_isDragging && mods.Ctrl && _interactionSystem?.IsPulling() == true && _interactionSystem.GetPulling() == targetMob)
				{
					StartDrag(targetMob, clickPos);
				}
				else if (!_isDragging)
				{
					RouteClick(targetMob, mods);
				}
			}
			else if (!_isDragging)
			{
				_movementController?.FacePosition(clickPos);
			}
		}
		GetViewport().SetInputAsHandled();
	}
	
	private void HandleMouseReleased(InputEventMouseButton mouseEvent)
	{
		var mouseUpPos = GetGlobalMousePosition();
		var dragDistance = _mouseDownPos.DistanceTo(mouseUpPos);
		var pressDuration = _mouseDownTime;
		
		GD.Print($"[ClickManager] HandleMouseReleased: state={_worldItemInteractionState}, _mouseDownItem={(_mouseDownItem?.ItemData?.ItemName ?? "null")}, dragDistance={dragDistance}, pressDuration={pressDuration}");
		
		if (_isDragging)
		{
			HandleDragEnd(mouseUpPos);
		}
		else if (_worldItemInteractionState == MouseInteractionState.Pressed && _mouseDownItem != null)
		{
			if (_worldItemInteractionState != MouseInteractionState.Dragging)
			{
				GD.Print($"[ClickManager] Still in PRESSED state - calling HandleWorldItemClick");
				HandleWorldItemClick();
				GetViewport().SetInputAsHandled();
			}
		}
		
		_worldItemInteractionState = MouseInteractionState.Idle;
		_mouseDownItem = null;
	}
	
	private void HandleWorldItemClick()
	{
		if (_mouseDownItem == null) 
		{
			GD.PrintErr("[ClickManager] HandleWorldItemClick called but _mouseDownItem is null!");
			return;
		}
		
		GD.Print($"[ClickManager] HandleWorldItemClick: clicked item = {_mouseDownItem.ItemData?.ItemName ?? "null"}");
		
		float timeSinceLastClick = (float)(Time.GetTicksMsec() / 1000.0) - _lastClickTime;
		_lastClickTime = (float)(Time.GetTicksMsec() / 1000.0);
		
		if (timeSinceLastClick < DoubleClickThreshold)
		{
			GD.Print($"[ClickManager] Double-click detected on {_mouseDownItem.ItemData?.ItemName}");
			_mouseDownItem.HandleWorldItemDoubleClick();
		}
		else
		{
			GD.Print($"[ClickManager] Single-click detected on {_mouseDownItem.ItemData?.ItemName}, calling HandleWorldItemClick");
			_mouseDownItem.HandleWorldItemClick();
		}
	}
	
	private ClickModifiers GatherModifiers()
	{
		return new ClickModifiers
		{
			Ctrl = Input.IsKeyPressed(Key.Ctrl),
			Shift = Input.IsKeyPressed(Key.Shift),
			Alt = Input.IsKeyPressed(Key.Alt)
		};
	}
	
	private void RouteClick(Mob target, ClickModifiers mods)
	{
		_nextClick = (float)(Time.GetTicksMsec() / 1000.0f) + ClickCooldown;
		
		if (mods.Shift)
		{
			_interactionSystem?.ExamineTarget(target);
			return;
		}
		
		if (mods.Ctrl)
		{
			RequestServerAction(nameof(ServerGrabClick), target);
			return;
		}
		
		if (mods.Alt)
		{
			RequestServerAction(nameof(ServerPullClick), target);
			return;
		}
		
		if (_intentSystem != null)
		{
			var intent = _intentSystem.GetIntent();
			RequestServerAction(nameof(ServerIntentInteraction), target, intent);
		}
		else
		{
			RequestServerAction(nameof(ServerInteract), target);
		}
	}
	
	private Vector2? _dragStartPos;
	private Mob _dragTarget;
	private bool _isDragging;
	
	private enum MouseInteractionState
	{
		Idle,
		Pressed,
		Dragging
	}
	
	private MouseInteractionState _worldItemInteractionState = MouseInteractionState.Idle;
	private WorldItem _mouseDownItem;
	private Vector2 _mouseDownPos;
	private float _mouseDownTime = 0f;
	private float _lastClickTime = 0f;
	
	private const float DragDistanceThreshold = 10f;
	private const float DragTimeThreshold = 0.2f;
	private const float DoubleClickThreshold = 0.3f;
	
	private void StartDrag(Mob target, Vector2 clickPos)
	{
		_dragTarget = target;
		_dragStartPos = clickPos;
		_isDragging = true;
	}
	
	private void HandleDragUpdate()
	{
		if (!_isDragging || _dragTarget == null) return;
	}
	
	private void HandleDragEnd(Vector2 dropPosition)
	{
		if (!_isDragging || _dragTarget == null)
		{
			_isDragging = false;
			_dragTarget = null;
			_dragStartPos = null;
			return;
		}
		
		if (Multiplayer.IsServer())
		{
			_interactionSystem?.StartDragCarry(dropPosition);
		}
		else
		{
			RpcId(1, nameof(ServerStartFiremanCarryRpc), _mob.GetMultiplayerAuthority(), dropPosition);
		}
		
		_isDragging = false;
		_dragTarget = null;
		_dragStartPos = null;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerStartFiremanCarryRpc(int ownerPeerId, Vector2 dropPosition)
	{
		if (!Multiplayer.IsServer()) return;
		var senderId = Multiplayer.GetRemoteSenderId();
		if (senderId > 0 && ownerPeerId > 0 && senderId != ownerPeerId)
			return;
		var resolvedPeer = senderId > 0 ? senderId : ownerPeerId;
		var world = GetTree().GetFirstNodeInGroup("World");
		var mob = world?.GetNodeOrNull(resolvedPeer.ToString()) as Mob;
		mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.StartDragCarry(dropPosition);
	}
	
	private Vector2I WorldToGrid(Vector2 worldPos)
	{
		return new Vector2I(
			(int)Mathf.Floor(worldPos.X / 32),
			(int)Mathf.Floor(worldPos.Y / 32)
		);
	}
	
	private void RequestServerAction(string action, Mob target)
	{
		if (Multiplayer.IsServer())
		{
			switch (action)
			{
				case nameof(ServerGrabClick):
					_interactionSystem?.StartPull(target);
					break;
				case nameof(ServerPullClick):
					_interactionSystem?.StartPull(target);
					break;
				case nameof(ServerInteract):
					_interactionSystem?.InteractWithMob(target);
					break;
				case nameof(ServerIntentInteraction):
					break;
			}
		}
		else
		{
			RpcId(1, action, _mob.GetMultiplayerAuthority(), target.GetMultiplayerAuthority());
		}
	}
	
	private void RequestServerAction(string action, Mob target, Intent intent)
	{
		if (Multiplayer.IsServer())
		{
			switch (action)
			{
				case nameof(ServerIntentInteraction):
					_interactionSystem?.InteractWithMob(target, intent);
					break;
			}
		}
		else
		{
			RpcId(1, action, _mob.GetMultiplayerAuthority(), target.GetMultiplayerAuthority(), (int)intent);
		}
	}
	
	private struct ClickModifiers
	{
		public bool Ctrl;
		public bool Shift;
		public bool Alt;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerGrabClick(int ownerPeerId, int targetPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var owner = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		var target = world?.GetNodeOrNull(targetPeerId.ToString()) as Mob;
		owner?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.StartPull(target);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerPullClick(int ownerPeerId, int targetPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var owner = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		var target = world?.GetNodeOrNull(targetPeerId.ToString()) as Mob;
		owner?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.StartPull(target);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerInteract(int ownerPeerId, int targetPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var owner = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		var target = world?.GetNodeOrNull(targetPeerId.ToString()) as Mob;
		owner?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.InteractWithMob(target);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerIntentInteraction(int ownerPeerId, int targetPeerId, int intent)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var owner = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		var target = world?.GetNodeOrNull(targetPeerId.ToString()) as Mob;
		var interactionSystem = owner?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		
		if (owner != null && target != null && interactionSystem != null)
		{
			interactionSystem.InteractWithMob(target, (Intent)intent);
		}
	}
}
