using Godot;

public enum GrabLevel { None = 0, Passive = 1, Aggressive = 2, Choke = 3, Fireman = 4 }

public partial class PlayerInteractionSystem : Node, IMobSystem
{
	private Mob _owner;
	private Mob _pullingTarget;
	private Mob _pulledBy;
	private GrabLevel _grabLevel = GrabLevel.None;
	private GrabItem _grabItem;
	private float _nextInteractionTime;
	
	private GridSystem _gridSystem;
	private SkillComponent _skillSystem;
	private DoAfterComponent _doAfter;
	private IntentSystem _intentSystem;
	private Inventory _inventory;
	
	[Signal] public delegate void StartedPullingEventHandler(Mob target);
	[Signal] public delegate void StoppedPullingEventHandler();
	[Signal] public delegate void GrabLevelChangedEventHandler(int level);
	
	public void Init(Mob mob)
	{
		_owner = mob;
		_gridSystem = FindGridSystem();
		_skillSystem = mob.GetNodeOrNull<SkillComponent>("SkillComponent");
		_doAfter = mob.GetNodeOrNull<DoAfterComponent>("DoAfterComponent");
		_intentSystem = mob.GetNodeOrNull<IntentSystem>("IntentSystem");
		_inventory = mob.GetNodeOrNull<Inventory>("Inventory");
	}
	
	public void Process(double delta)
	{
		if (_pullingTarget != null && !IsInstanceValid(_pullingTarget))
		{
			StopPull();
			return;
		}

		if (Multiplayer.IsServer() && _pullingTarget != null && !HasGrabItemEquipped())
		{
			StopPull();
			return;
		}
		
		if (_pullingTarget != null && _grabLevel > GrabLevel.None)
		{
			CheckForGripLoss();
		}

		if (_pullingTarget != null && _gridSystem != null && _grabLevel == GrabLevel.Fireman)
		{
			UpdateFiremanCarryPosition();
		}
		
		if (_pulledBy != null)
			return;
		
		if (_owner.DisableMovement)
			_owner.DisableMovement = false;
	}

	public void InteractWithMob(Mob target, Intent? intentOverride = null)
	{
		if (!Multiplayer.IsServer()) return;
		if (target == null || target == _owner) return;

		if (!CanInteract())
			return;

		var now = (float)(Time.GetTicksMsec() / 1000.0);
		if (now < _nextInteractionTime)
			return;
		
		var intent = intentOverride ?? _intentSystem?.GetIntent() ?? Intent.Help;
		var ownerTile = _gridSystem.WorldToGrid(_owner.GlobalPosition);
		var targetTile = _gridSystem.WorldToGrid(target.GlobalPosition);
		
		GD.Print($"[PlayerInteraction] {(_owner.GetPlayerName() ?? "Unknown")} attempting {intent} interaction with {target.GetPlayerName()} at distance {ownerTile.DistanceTo(targetTile)}");
		
		if (!_gridSystem.IsAdjacent(ownerTile, targetTile))
		{
			GD.Print($"[PlayerInteraction] Interaction blocked: too far away ({ownerTile} vs {targetTile})");
			_owner.ShowChatBubble("Too far away");
			return;
		}
		
		GD.Print($"[PlayerInteraction] Executing {intent} interaction with {target.GetPlayerName()}");
		
		var movement = _owner.GetNodeOrNull<MovementController>("MovementController");
		movement?.FacePosition(target.GlobalPosition);
		
		switch (intent)
		{
			case Intent.Help:
				HandleHelpIntent(target);
				break;
			case Intent.Disarm:
				HandleDisarmIntent(target);
				break;
			case Intent.Grab:
				HandleGrabIntent(target);
				break;
			case Intent.Harm:
				HandleHarmIntent(target);
				break;
			default:
				GD.Print($"[PlayerInteraction] Unknown intent: {intent}");
				break;
		}

		_nextInteractionTime = now + 1.0f;
	}
	
	private void HandleHelpIntent(Mob target)
	{
		GD.Print($"[PlayerInteraction] Help intent: {(_owner.GetPlayerName() ?? "Unknown")} helping {target.GetPlayerName()}");
		
		if (GD.Randf() > 0.5f)
		{
			GD.Print($"[PlayerInteraction] Help action: hug");
			_owner.ShowPrivateThought("I hug them");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} hugs you");
		}
		else
		{
			GD.Print($"[PlayerInteraction] Help action: pat");
			_owner.ShowPrivateThought("I pat them on the back");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} pats you on the back");
		}
		
		var targetState = target.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (targetState != null)
		{
			targetState.HelpUp();
		}
	}
	
	private void HandleDisarmIntent(Mob target)
	{
		var targetSkill = target.GetNodeOrNull<SkillComponent>("SkillComponent");
		int ownerCQC = _skillSystem?.GetSkillLevel(SkillType.CQC) ?? 0;
		int targetCQC = targetSkill?.GetSkillLevel(SkillType.CQC) ?? 0;
		
		float stunChance = 0.15f + (ownerCQC * 0.1f) - (targetCQC * 0.05f);
		stunChance = Mathf.Clamp(stunChance, 0.05f, 0.75f);
		
		Rpc(nameof(PlayThrustAnimationRpc), target.GlobalPosition);
		
		if (GD.Randf() < stunChance)
		{
			var targetState = target.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			if (targetState != null)
			{
				targetState.SetStunned(1.0f);
			}
			
			_owner.ShowPrivateThought("I disarm and shove them to the ground");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} disarms and shoves you to the ground!");
		}
		else
		{
			_owner.ShowPrivateThought("I try to disarm them");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} tries to disarm you");
		}
	}
	
	private void HandleGrabIntent(Mob target)
	{
		GD.Print($"[PlayerInteraction] Grab intent: {(_owner.GetPlayerName() ?? "Unknown")} attempting to grab {target.GetPlayerName()}");
		
		if (_pullingTarget != null)
		{
			if (_pullingTarget == target)
			{
				GD.Print($"[PlayerInteraction] Grab blocked: already grabbing {target.GetPlayerName()}");
				_owner.ShowPrivateThought("I'm already grabbing them");
			}
			else
			{
				GD.Print($"[PlayerInteraction] Grab blocked: already grabbing someone else");
				_owner.ShowPrivateThought("I'm already grabbing someone else");
			}
		}
		else
		{
			GD.Print($"[PlayerInteraction] Grab successful: starting pull on {target.GetPlayerName()}");
			StartPull(target);
		}
	}
	
	private void HandleHarmIntent(Mob target)
	{
		GD.Print($"[PlayerInteraction] Harm intent: {(_owner.GetPlayerName() ?? "Unknown")} attacking {target.GetPlayerName()}");
		
		var targetSkill = target.GetNodeOrNull<SkillComponent>("SkillComponent");
		int ownerCQC = _skillSystem?.GetSkillLevel(SkillType.CQC) ?? 0;
		int targetCQC = targetSkill?.GetSkillLevel(SkillType.CQC) ?? 0;
		
		float hitChance = 0.6f + (ownerCQC * 0.08f) - (targetCQC * 0.04f);
		hitChance = Mathf.Clamp(hitChance, 0.3f, 0.95f);
		
		GD.Print($"[PlayerInteraction] Harm calculation: ownerCQC={ownerCQC}, targetCQC={targetCQC}, hitChance={hitChance:P1}");
		
		if (GD.Randf() < hitChance)
		{
			float damage = 5.0f + (ownerCQC * 2.0f);
			var targetHealth = target.GetNodeOrNull<HealthSystem>("HealthSystem");
			targetHealth?.ApplyDamage(DamageType.Brute, damage, _owner.GetPlayerName());
			
			GD.Print($"[PlayerInteraction] Harm successful: dealt {damage} damage to {target.GetPlayerName()}");
			_owner.ShowPrivateThought("I punch them");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} punches you!");
			Rpc(nameof(PlayThrustAnimationRpc), target.GlobalPosition);
			target.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.Rpc(nameof(PlayHitEffectRpc), target.GlobalPosition);
		}
		else
		{
			GD.Print($"[PlayerInteraction] Harm missed: {(_owner.GetPlayerName() ?? "Unknown")} missed {target.GetPlayerName()}");
			_owner.ShowPrivateThought("I miss them");
			target.ShowPrivateMessageTo(target.GetMultiplayerAuthority(), $"{_owner.GetPlayerName()} misses you");
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void PlayHitEffectRpc(Vector2 position)
	{
		var spriteSystem = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		spriteSystem?.PlayHitEffect(position);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void PlayThrustAndHitRpc(Vector2 targetPosition, Vector2 hitPosition)
	{
		var spriteSystem = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		spriteSystem?.PlayThrustAndHitEffect(targetPosition - _owner.GlobalPosition, hitPosition);
	}
	
	public void StartPull(Mob target)
	{
		if (!Multiplayer.IsServer()) return;
		if (target == null || target == _owner) return;
		
		var targetInteraction = target.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		if (targetInteraction?._pulledBy != null)
		{
			_owner.ShowChatBubble("Already being pulled");
			return;
		}
		
		var activeSlot = _inventory.GetActiveHand() == 0 ? "left_hand" : "right_hand";
		if (_inventory.GetEquipped(activeSlot) != null)
		{
			_owner.ShowChatBubble("Hand is occupied");
			return;
		}
		
		_pullingTarget = target;
		_grabLevel = GrabLevel.Passive;
		targetInteraction._pulledBy = _owner;
		targetInteraction.Rpc(nameof(SyncPulledByRpc), _owner.GetPath());
		_grabItem = new GrabItem();
		_inventory.Equip(_grabItem, activeSlot);
		
		EmitSignal(SignalName.StartedPulling, target);
		_owner.ShowChatBubble($"grabs {target.GetPlayerName()}");
		
		Rpc(nameof(SyncStartPullRpc), target.GetPath());
		UpdatePullerSpeed();
	}
	
	public void StopPull()
	{
		if (!Multiplayer.IsServer()) return;
		if (_pullingTarget == null) return;
		
		var targetInteraction = _pullingTarget.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		if (targetInteraction != null)
		{
			targetInteraction._pulledBy = null;
			targetInteraction.Rpc(nameof(ClearPulledByRpc));
			_pullingTarget.DisableMovement = false;
		}
		
		if (_grabLevel == GrabLevel.Fireman)
		{
			var targetState = _pullingTarget.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			targetState?.SetState(MobState.Standing);
		}
		
		var activeSlot = _inventory.GetActiveHand() == 0 ? "left_hand" : "right_hand";
		_inventory.Unequip(activeSlot);
		_grabItem = null;
		
		_pullingTarget = null;
		_grabLevel = GrabLevel.None;
		UpdatePullerSpeed();
		
		EmitSignal(SignalName.StoppedPulling);
		Rpc(nameof(SyncStopPullRpc));
	}
	
	public void ProgressGrab()
	{
		if (!Multiplayer.IsServer()) return;
		if (_pullingTarget == null) return;
		
		if (_grabLevel == GrabLevel.Passive)
		{
			_grabLevel = GrabLevel.Aggressive;
			var targetState = _pullingTarget.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			targetState?.SetState(MobState.Prone);
			
			_owner.ShowChatBubble($"aggressively grabs {_pullingTarget.GetPlayerName()}!");
			Rpc(nameof(SyncGrabLevelRpc), (int)_grabLevel);
			UpdatePullerSpeed();
		}
		else if (_grabLevel == GrabLevel.Aggressive)
		{
			_grabLevel = GrabLevel.Choke;
			_owner.ShowChatBubble($"starts choking {_pullingTarget.GetPlayerName()}!");
			Rpc(nameof(SyncGrabLevelRpc), (int)_grabLevel);
			UpdatePullerSpeed();
		}
	}
	
	public void StartFiremanCarry(Vector2 dropPosition)
	{
		if (!Multiplayer.IsServer()) return;
		if (_pullingTarget == null) return;
		if (!_pullingTarget.CanBeDragCarried) return;
		if (_grabLevel < GrabLevel.Aggressive)
		{
			_grabLevel = GrabLevel.Aggressive;
			var targetState = _pullingTarget.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			targetState?.SetState(MobState.Prone);
			Rpc(nameof(SyncGrabLevelRpc), (int)_grabLevel);
			UpdatePullerSpeed();
		}

		float carryTime = CalculateCarryTime();
		var spriteSystem = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		spriteSystem?.PlayDoAfterAnimation(carryTime);
		
		_doAfter?.StartAction(carryTime, 
			onComplete: () => {
				_grabLevel = GrabLevel.Fireman;
				var targetState = _pullingTarget.GetNodeOrNull<MobStateSystem>("MobStateSystem");
				targetState?.SetState(MobState.Grabbed);
				
				_pullingTarget.GlobalPosition = _owner.GlobalPosition;
				
				_owner.ShowChatBubble($"lifts {_pullingTarget.GetPlayerName()} onto shoulder");
				Rpc(nameof(SyncGrabLevelRpc), (int)_grabLevel);
				EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
			},
			onCancel: () => {
				_owner.ShowChatBubble("Stopped carrying");
			}
		);
	}
	
	private float CalculateCarryTime()
	{
		int skillLevel = _skillSystem?.GetSkillLevel(SkillType.FiremanCarry) ?? 0;
		float baseTime = 3.0f;
		float reduction = skillLevel * 0.3f;
		return Mathf.Max(1.0f, baseTime - reduction);
	}
	
	private void UpdateFiremanCarryPosition()
	{
		if (_pullingTarget == null) return;
		
		var offset = GetCarryOffset();
		_pullingTarget.GlobalPosition = _owner.GlobalPosition + offset;
		
		Rpc(nameof(SyncPullPositionRpc), _pullingTarget.GetPath(), _pullingTarget.GlobalPosition);
	}
	
	private Vector2 GetCarryOffset()
	{
		var spriteSystem = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		int direction = spriteSystem?.Direction ?? 0;
		
		return direction switch
		{
			0 => new Vector2(16, 0),
			1 => new Vector2(-16, 0),
			2 => new Vector2(0, 16),
			3 => new Vector2(0, -16),
			_ => new Vector2(16, 0)
		};
	}
	
	private void CheckForGripLoss()
	{
		if (_pullingTarget == null || _grabLevel <= GrabLevel.None) return;
		
		var expectedTile = _gridSystem.WorldToGrid(_owner.GlobalPosition);
		var actualTile = _gridSystem.WorldToGrid(_pullingTarget.GlobalPosition);
		
		var distance = expectedTile - actualTile;
		if (Mathf.Abs(distance.X) > 2 || Mathf.Abs(distance.Y) > 2)
		{
			_owner.ShowChatBubble($"lost grip on {_pullingTarget.GetPlayerName()}");
			StopPull();
		}
	}

	public void StartDragCarry(Vector2 dropPosition)
	{
		if (!Multiplayer.IsServer()) return;
		if (_pullingTarget == null || !_pullingTarget.CanBeDragCarried) return;
		
		_grabLevel = GrabLevel.Fireman;
		var targetState = _pullingTarget.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		targetState?.SetState(MobState.Grabbed);
		
		_pullingTarget.GlobalPosition = _owner.GlobalPosition;
		
		_owner.ShowChatBubble($"lifts {_pullingTarget.GetPlayerName()} onto shoulder");
		Rpc(nameof(SyncGrabLevelRpc), (int)_grabLevel);
		EmitSignal(SignalName.GrabLevelChanged, (int)_grabLevel);
		UpdatePullerSpeed();
	}
	
	public void OnIntentChanged(Intent newIntent)
	{
		if (_grabLevel > GrabLevel.None && newIntent != Intent.Grab)
		{
			GD.Print($"[PlayerInteraction] Intent changed from Grab to {newIntent}, stopping pull");
			StopPull();
		}
	}
	
	public void ExamineTarget(Mob target)
	{
		if (target == null) return;
		
		var health = target.GetNodeOrNull<HealthSystem>("HealthSystem");
		var state = target.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		
		string examination = $"This is {target.GetPlayerName()}.";
		
		if (health != null)
		{
			float healthPercent = health.GetHealthPercentage();
			if (healthPercent > 90)
				examination += " They appear healthy.";
			else if (healthPercent > 60)
				examination += " They have some injuries.";
			else if (healthPercent > 30)
				examination += " They are badly injured.";
			else
				examination += " They are in critical condition!";
		}
		
		if (state != null)
		{
			examination += state.GetState() switch
			{
				MobState.Prone => " They are lying down.",
				MobState.Sleeping => " They appear to be sleeping.",
				MobState.Critical => " They are unconscious!",
				MobState.Dead => " They are not breathing...",
				MobState.Grabbed => " They are being held.",
				_ => ""
			};
		}
		
		_owner.ShowChatBubble(examination);
	}
	
	public void HandleActivate()
	{
		if (!CanInteract())
			return;

		if (_pullingTarget != null)
		{
			ProgressGrab();
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStartPullRpc(NodePath targetPath)
	{
		var target = GetNodeOrNull<Mob>(targetPath);
		if (target != null)
		{
			_pullingTarget = target;
			_grabLevel = GrabLevel.Passive;
			EmitSignal(SignalName.StartedPulling, target);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStopPullRpc()
	{
		if (_pullingTarget != null)
		{
			_pullingTarget.DisableMovement = false;
		}
		_pullingTarget = null;
		_grabLevel = GrabLevel.None;
		EmitSignal(SignalName.StoppedPulling);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncGrabLevelRpc(int level)
	{
		_grabLevel = (GrabLevel)level;
		EmitSignal(SignalName.GrabLevelChanged, level);
		UpdatePullerSpeed();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPullPositionRpc(NodePath targetPath, Vector2 position)
	{
		var target = GetNodeOrNull<Mob>(targetPath);
		if (target != null)
		{
			target.GlobalPosition = position;
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPulledByRpc(NodePath ownerPath)
	{
		_pulledBy = GetNodeOrNull<Mob>(ownerPath);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClearPulledByRpc()
	{
		_pulledBy = null;
		_owner.DisableMovement = false;
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPullStepRpc(NodePath targetPath, Vector2I targetTile, bool ignoreEntities)
	{
		if (_grabLevel >= GrabLevel.Fireman) return;

		var target = GetNodeOrNull<Mob>(targetPath);
		if (target == null) return;

		var targetInteraction = target.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		if (targetInteraction?._pulledBy != _owner) return;

		MovePulledTarget(target, targetTile, ignoreEntities);
	}
	
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void PlayThrustAnimationRpc(Vector2 targetPosition)
	{
		var spriteSystem = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		spriteSystem?.PlayThrustTween(targetPosition - _owner.GlobalPosition);
	}

	public void OnOwnerMovementStarted(Vector2I ownerTile, Vector2I ownerTargetTile)
	{
		if (_pullingTarget == null || _grabLevel >= GrabLevel.Fireman) return;

		if (!Multiplayer.IsServer())
			RpcId(1, nameof(ServerPullStepRpc), _owner.GetPath(), ownerTile, ownerTargetTile);

		HandlePullStepFromTiles(ownerTile, ownerTargetTile, Multiplayer.IsServer());
	}

	private void HandlePullStepFromTiles(Vector2I ownerTile, Vector2I ownerTargetTile, bool broadcast)
	{
		if (_pullingTarget == null || _gridSystem == null) return;

		if (ownerTile == ownerTargetTile) return;

		var targetTile = _gridSystem.WorldToGrid(_pullingTarget.GlobalPosition);
		var shouldSwap = targetTile == ownerTargetTile;
		var shouldFollow = shouldSwap || IsAdjacentOneStep(targetTile, ownerTargetTile);

		var desiredTile = shouldFollow ? ownerTile : StepToward(targetTile, ownerTargetTile);
		if (!shouldSwap && desiredTile == ownerTargetTile)
			desiredTile = StepToward(targetTile, ownerTile);
		var ignoreEntities = shouldFollow || desiredTile == ownerTile;

		if (desiredTile == targetTile) return;
		if (!MovePulledTarget(_pullingTarget, desiredTile, ignoreEntities)) return;

		if (broadcast)
			Rpc(nameof(SyncPullStepRpc), _pullingTarget.GetPath(), desiredTile, ignoreEntities);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerBreakPullRpc(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = GetNodeOrNull<Mob>(mobPath);
		mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.BreakPullAndStun();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerPullStepRpc(NodePath ownerPath, Vector2I ownerTile, Vector2I ownerTargetTile)
	{
		if (!Multiplayer.IsServer()) return;

		var owner = GetNodeOrNull<Mob>(ownerPath);
		var interaction = owner?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		if (interaction == null || interaction._pullingTarget == null || interaction._grabLevel >= GrabLevel.Fireman)
			return;

		interaction.HandlePullStepFromTiles(ownerTile, ownerTargetTile, true);
	}

	private bool MovePulledTarget(Mob target, Vector2I targetTile, bool ignoreEntities)
	{
		var targetMovement = target.GetNodeOrNull<MovementController>("MovementController");
		if (targetMovement == null) return false;

		if (!targetMovement.TryStartForcedMovement(targetTile, ignoreEntities, true))
			return false;

		return true;
	}

	public void OnPulledMoveAttempt()
	{
		if (_pulledBy == null) return;

		if (Multiplayer.IsServer())
		{
			BreakPullAndStun();
		}
		else
		{
			RpcId(1, nameof(ServerBreakPullRpc), _owner.GetPath());
		}
	}

	private void BreakPullAndStun()
	{
		if (_pulledBy == null) return;

		var pullerInteraction = _pulledBy.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		pullerInteraction?.StopPull();

		var state = _owner.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		state?.SetState(MobState.Stunned, 1.0f);
	}

	private void UpdatePullerSpeed()
	{
		var movement = _owner.GetNodeOrNull<MovementController>("MovementController");
		if (movement == null) return;

		if (_pullingTarget == null)
		{
			movement.SetInteractionSpeedMultiplier(1.0f);
			return;
		}

		if (_grabLevel >= GrabLevel.Aggressive)
			movement.SetInteractionSpeedMultiplier(0.35f);
		else
			movement.SetInteractionSpeedMultiplier(1.0f);
	}

	private bool CanInteract()
	{
		var state = _owner.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (state == null) return true;
		return state.GetState() == MobState.Standing;
	}

	private bool HasGrabItemEquipped()
	{
		if (_inventory == null) return false;
		return _inventory.GetEquipped("left_hand") is GrabItem || _inventory.GetEquipped("right_hand") is GrabItem;
	}

	private static bool IsAdjacentOneStep(Vector2I a, Vector2I b)
	{
		var dx = Mathf.Abs(a.X - b.X);
		var dy = Mathf.Abs(a.Y - b.Y);
		return dx <= 1 && dy <= 1;
	}

	private Vector2I StepToward(Vector2I from, Vector2I to)
	{
		var dx = Mathf.Clamp(to.X - from.X, -1, 1);
		var dy = Mathf.Clamp(to.Y - from.Y, -1, 1);
		return new Vector2I(from.X + dx, from.Y + dy);
	}
	
	public bool IsPulling() => _pullingTarget != null;
	public Mob GetPulling() => _pullingTarget;
	public int GetGrabLevel() => (int)_grabLevel;
	public Mob GetPulledBy() => _pulledBy;
	
	private GridSystem FindGridSystem()
	{
		Node current = _owner;
		while (current != null)
		{
			var grid = current.GetNodeOrNull<GridSystem>("GridSystem");
			if (grid != null) return grid;
			current = current.GetParent();
		}
		return null;
	}
	
	public void Cleanup()
	{
		if (_pullingTarget != null)
			StopPull();
	}
}
