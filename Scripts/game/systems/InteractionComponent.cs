using Godot;
using System.Collections.Generic;

public partial class InteractionComponent : Node, IMobSystem
{
	private Mob _owner;
	private Inventory _inventory;
	private int _activeHand;
	private bool _throwMode;
	private bool _longThrowMode;
	private bool _isThrowing;
	private float _throwCooldown = 0.0f;
	
	[Signal] public delegate void HandSwitchedEventHandler(int hand);
	[Signal] public delegate void LimbSelectedEventHandler(string limbName);
	
	public void Init(Mob mob)
	{
		_owner = mob;
		_inventory = mob.GetNodeOrNull<Inventory>("Inventory");
		if (_inventory != null)
			_activeHand = _inventory.GetActiveHand();
		
		GD.Print($"[InteractionComponent] Init called for {mob.Name}, IsMultiplayerAuthority={mob.IsMultiplayerAuthority()}");
		SetProcessUnhandledInput(true);
	}
	
	public override void _Ready()
	{
		GD.Print($"[InteractionComponent] _Ready called");
		SetProcessUnhandledInput(true);
	}
	
	public override void _UnhandledInput(InputEvent @event)
	{
		if (_owner == null)
		{
			GD.PrintErr("[InteractionComponent] _UnhandledInput called but _owner is null!");
			return;
		}
		
		if (!_owner.IsMultiplayerAuthority())
		{
			return;
		}
		
		if (@event is InputEventKey keyEvent)
		{
			GD.Print($"[InteractionComponent] Unhandled key event: {keyEvent.Keycode}, Pressed={keyEvent.Pressed}");
		}
		
		var state = _owner.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (state != null && state.GetState() != MobState.Standing)
			return;
		
		if (@event.IsActionPressed("switch_hand"))
		{
			GD.Print("[InteractionComponent] switch_hand pressed");
			SwitchHands();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("drop"))
		{
			GD.Print("[InteractionComponent] drop pressed");
			DropActive();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("throw_toggle"))
		{
			GD.Print("[InteractionComponent] throw_toggle pressed!");
			
			if (@event is InputEventKey keyEvent2 && keyEvent2.ShiftPressed)
			{
				GD.Print("[InteractionComponent] Shift is pressed, ignoring");
				return;
			}
			
			bool isCtrlPressed = Input.IsKeyPressed(Key.Ctrl);
			GD.Print($"[InteractionComponent] Ctrl={isCtrlPressed}");
			
			if (isCtrlPressed)
			{
				_longThrowMode = !_longThrowMode;
				if (_longThrowMode)
					_throwMode = false;
				GD.Print($"[InteractionComponent] Long throw mode: {_longThrowMode}");
			}
			else
			{
				_throwMode = !_throwMode;
				if (_throwMode)
					_longThrowMode = false;
				GD.Print($"[InteractionComponent] Normal throw mode: {_throwMode}");
			}
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("activate"))
		{
			GD.Print("[InteractionComponent] activate pressed");
			ActivateHeld();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("quick_pickup"))
		{
			GD.Print("[InteractionComponent] quick_pickup pressed");
			_inventory?.QuickPickup();
			GetViewport().SetInputAsHandled();
		}
	}
	
	public void SwitchHands()
	{
		if (Multiplayer.IsServer())
		{
			SwapHandLocal();
			Rpc(nameof(SyncHandSwap));
		}
		else
		{
			RpcId(1, nameof(ServerSwapHand), _owner.GetMultiplayerAuthority());
		}
	}
	
	private void SwapHandLocal()
	{
		_activeHand = 1 - _activeHand;
		_inventory?.SetActiveHand(_activeHand);
		EmitSignal(SignalName.HandSwitched, _activeHand);
	}
	
	public void DropActive()
	{
		if (_inventory == null) return;
		
		var slot = _activeHand == 0 ? "left_hand" : "right_hand";
		var item = _inventory.GetEquipped(slot);
		if (item == null)
		{
			var interactionSystem = _owner.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
			if (interactionSystem?.IsPulling() == true)
			{
				if (Multiplayer.IsServer())
					interactionSystem.StopPull();
				else
					RpcId(1, nameof(ServerReleaseGrab), _owner.GetMultiplayerAuthority(), slot);
			}
			return;
		}
		
		if (item is GrabItem)
		{
			if (Multiplayer.IsServer())
			{
				_inventory.Unequip(slot);
				_owner.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.StopPull();
			}
			else
			{
				RpcId(1, nameof(ServerReleaseGrab), _owner.GetMultiplayerAuthority(), slot);
			}
			return;
		}
		
		if (Multiplayer.IsServer())
		{
			_inventory.Unequip(slot);
			SpawnWorldItem(item, _owner.GlobalPosition);
		}
		else
		{
			RpcId(1, nameof(ServerDropItem), _owner.GetMultiplayerAuthority(), slot, _owner.GlobalPosition);
		}
	}
	
	public void ThrowActive(Vector2 targetPos)
	{
		if (_inventory == null) return;
		if (!_throwMode && !_longThrowMode) return;
		
		var slot = _activeHand == 0 ? "left_hand" : "right_hand";
		var item = _inventory.GetEquipped(slot);
		if (item == null) return;
		
		if (_throwCooldown > 0) return;
		
		if (_longThrowMode)
		{
			if (Multiplayer.IsServer())
			{
				PerformLongThrow(targetPos, slot, item);
			}
			else
			{
				RpcId(1, nameof(ServerPerformLongThrow), _owner.GetMultiplayerAuthority(), targetPos, slot, item.ItemName);
			}
		}
		else if (_throwMode)
		{
			if (Multiplayer.IsServer())
			{
				PerformNormalThrow(targetPos, slot, item);
			}
			else
			{
				RpcId(1, nameof(ServerPerformNormalThrow), _owner.GetMultiplayerAuthority(), targetPos, slot, item.ItemName);
			}
		}
	}
	
	private void PerformLongThrow(Vector2 targetPos, string slot, Item item)
	{
		if (_inventory == null) return;
		
		var currentItem = _inventory.GetEquipped(slot);
		if (currentItem == null || currentItem.ItemName != item.ItemName)
		{
			GD.Print("[InteractionComponent] Item changed during long throw");
			return;
		}
		
		_inventory.Unequip(slot);
		ThrowWorldItem(item, _owner.GlobalPosition, targetPos);
		
		_throwMode = false;
		_longThrowMode = false;
		_throwCooldown = 1.0f;
	}
	
	private void PerformNormalThrow(Vector2 targetPos, string slot, Item item)
	{
		var throwPath = GetThrowPath(_owner.GlobalPosition, targetPos);
		var interceptingMob = FindInterceptingMob(throwPath);
		
		_inventory.Unequip(slot);
		
		if (interceptingMob != null)
		{
			ThrowWorldItem(item, _owner.GlobalPosition, interceptingMob.GlobalPosition);
		}
		else
		{
			ThrowWorldItem(item, _owner.GlobalPosition, targetPos);
		}
		
		_throwMode = false;
		_throwCooldown = 0.5f;
	}
	
	private Godot.Collections.Array<Vector2> GetThrowPath(Vector2 startPos, Vector2 endPos)
	{
		var path = new Godot.Collections.Array<Vector2>();
		var direction = (endPos - startPos).Normalized();
		var distance = startPos.DistanceTo(endPos);
		var stepSize = 16.0f;
		
		for (float d = 0; d <= distance; d += stepSize)
		{
			path.Add(startPos + direction * d);
		}
		
		return path;
	}
	
	private Mob FindInterceptingMob(Godot.Collections.Array<Vector2> throwPath)
	{
		var world = _owner.GetTree().GetFirstNodeInGroup("World");
		if (world == null) return null;
		
		foreach (var pos in throwPath)
		{
			foreach (var node in world.GetChildren())
			{
				if (node is Mob mob && mob != _owner)
				{
					var mobPos = mob.GlobalPosition;
					var distance = pos.DistanceTo(mobPos);
					if (distance <= 32.0f)
					{
						return mob;
					}
				}
			}
		}
		
		return null;
	}
	
	private void ActivateHeld()
	{
		if (_inventory == null) return;
		
		var slot = _activeHand == 0 ? "left_hand" : "right_hand";
		var item = _inventory.GetEquipped(slot);
		
		if (item is GrabItem)
		{
			var interactionSystem = _owner.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
			if (Multiplayer.IsServer())
			{
				interactionSystem?.HandleActivate();
			}
			else
			{
				RpcId(1, nameof(ServerActivateGrab), _owner.GetMultiplayerAuthority());
			}
			return;
		}
		
		if (item == null) return;
		
		if (item is MedicalItem medical)
		{
			if (Multiplayer.IsServer())
			{
				_inventory.Unequip(slot);
				medical.ApplyTo(_owner);
			}
			else
			{
				RpcId(1, nameof(ServerActivate), _owner.GetMultiplayerAuthority(), slot);
			}
		}
		else if (item is ConsumableItem consumable)
		{
			if (Multiplayer.IsServer())
			{
				_inventory.Unequip(slot);
				_owner.GetNodeOrNull<HealthSystem>("HealthSystem")?.ApplyHealing(consumable.HealAmount);
			}
			else
			{
				RpcId(1, nameof(ServerActivate), _owner.GetMultiplayerAuthority(), slot);
			}
		}
		else if (item is ClothingItem clothing)
		{
			if (Multiplayer.IsServer())
				_inventory.TryEquipFromInventory(GetClothingSlot(clothing));
			else
				RpcId(1, nameof(ServerActivate), _owner.GetMultiplayerAuthority(), slot);
		}
	}
	
	private string GetClothingSlot(ClothingItem clothing)
	{
		return clothing.Slot switch
		{
			ClothingItem.ClothingSlot.Head => "head",
			ClothingItem.ClothingSlot.Eyes => "eyes",
			ClothingItem.ClothingSlot.Mask => "mask",
			ClothingItem.ClothingSlot.Ears => "ears_left",
			ClothingItem.ClothingSlot.Gloves => "gloves",
			ClothingItem.ClothingSlot.Uniform => "uniform",
			ClothingItem.ClothingSlot.Armor => "armor",
			ClothingItem.ClothingSlot.Shoes => "shoes",
			ClothingItem.ClothingSlot.Belt => "belt",
			ClothingItem.ClothingSlot.Back => "back",
			ClothingItem.ClothingSlot.Pouch => "pouch_left",
			_ => ""
		};
	}
	
	public async void SpawnWorldItem(Item item, Vector2 position)
	{
		if (item is GrabItem)
		{
			return;
		}
		
		var worldItem = await CreateWorldItem(item, position);
		if (worldItem != null)
			_inventory?.RememberDrop(worldItem);
	}
	
	private async void ThrowWorldItem(Item item, Vector2 spawnPos, Vector2 targetPos)
	{
		if (item is GrabItem)
		{
			return;
		}
		
		var worldItem = await CreateWorldItem(item, spawnPos);
		if (worldItem != null)
		{
			_inventory?.RememberDrop(worldItem);
			await _owner.ToSignal(_owner.GetTree().CreateTimer(0.1), "timeout");
			worldItem.ThrowToPosition(targetPos);
		}
	}
	
	private async System.Threading.Tasks.Task<WorldItem> CreateWorldItem(Item item, Vector2 position)
	{
		if (!Multiplayer.IsServer()) return null;
		
		var pool = _owner.GetTree().Root.GetNodeOrNull<ItemPoolManager>("ItemPoolManager");
		WorldItem worldItem = pool?.Get(item, position);
		var world = _owner.GetTree().GetFirstNodeInGroup("World");
		if (world == null) return null;
		
		if (worldItem == null)
		{
			var scene = LoadItemScene(item);
			if (scene != null)
			{
				worldItem = scene.Instantiate<WorldItem>();
			}
			else
			{
				worldItem = CreateRuntimeWorldItem(item);
			}

			if (worldItem == null) return null;
			worldItem.PrepareSpawn(position);
			world.AddChild(worldItem, true);
		}
		
		await _owner.ToSignal(_owner.GetTree(), "process_frame");
		worldItem.InitAtPosition(position);
		return worldItem;
	}
	
	private PackedScene LoadItemScene(Item item)
	{
		if (!string.IsNullOrEmpty(item.ScenePath))
			return GD.Load<PackedScene>(item.ScenePath);

		if (item is ClothingItem)
		{
			string path = item.ItemName switch
			{
				"Marine_CM_Uniform" => "uid://bafal7piiq62r",
				"Medical_Scrubs" => "uid://cmekjlejs76dx",
				"MA_Light_Armor" => "uid://dokjyi8xbqq3f",
				"MA_Medium_Armor" => "uid://vcq5pgy5hx6q",
				"MA_Heavy_Armor" => "uid://bivuy3j7hqmiy",
				"Marine_Boots" => "uid://cm766a6sb2g85",
				"Combat_Boots" => "uid://3u2w8gvxgm1l",
				"Marine_Gloves" => "uid://eafyncq222qn",
				"Armored_Gloves" => "uid://bcijgf8bgu24c",
				_ => null
			};
			return path != null ? GD.Load<PackedScene>(path) : null;
		}

		return null;
	}

	private WorldItem CreateRuntimeWorldItem(Item item)
	{
		if (item == null) return null;

		var runtimeItem = new WorldItem
		{
			Name = string.IsNullOrEmpty(item.ItemName) ? "RuntimeItem" : item.ItemName,
			ItemId = item.ItemName,
			ItemData = item
		};

		var icon = new ItemSpriteSystem
		{
			Name = "Icon",
			IconTexture = item.Icon,
			IconHframes = Mathf.Max(1, item.IconHframes),
			IconVframes = Mathf.Max(1, item.IconVframes),
			DefaultStateId = "default"
		};
		runtimeItem.AddChild(icon);
		return runtimeItem;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerSwapHand(int ownerPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		mob?.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.SwitchHands();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncHandSwap()
	{
		SwapHandLocal();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerDropItem(int ownerPeerId, string slot, Vector2 position)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = ResolveMobForRpc(ownerPeerId);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null)
		{
			inventory.Unequip(slot);
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.SpawnWorldItem(item, position);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerThrowItem(int ownerPeerId, string slot, Vector2 spawnPos, Vector2 targetPos)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = ResolveMobForRpc(ownerPeerId);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null)
		{
			inventory.Unequip(slot);
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.ThrowWorldItem(item, spawnPos, targetPos);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerActivate(int ownerPeerId, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		mob?.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.ActivateHeld();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerActivateGrab(int ownerPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.HandleActivate();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerReleaseGrab(int ownerPeerId, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var interactionSystem = mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		
		if (inventory != null && interactionSystem != null)
		{
			inventory.Unequip(slot);
			interactionSystem.StopPull();
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerPerformLongThrow(int ownerPeerId, Vector2 targetPos, string slot, string itemName)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null && item.ItemName == itemName)
		{
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.PerformLongThrow(targetPos, slot, item);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerPerformNormalThrow(int ownerPeerId, Vector2 targetPos, string slot, string itemName)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null && item.ItemName == itemName)
		{
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.PerformNormalThrow(targetPos, slot, item);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerSetSelectedLimb(int ownerPeerId, string limbName)
	{
		if (!Multiplayer.IsServer()) return;
		var mob = ResolveMobForRpc(ownerPeerId);
		mob?.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.SetSelectedLimb(limbName);
	}
	
	public int GetActiveHand() => _activeHand;
	public bool IsThrowMode() => _throwMode;
	public bool IsLongThrowMode() => _longThrowMode;
	
	public bool IsPullMode()
	{
		var interactionSystem = _owner.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		return interactionSystem?.IsPulling() == true;
	}
	
	public void ToggleLongThrowMode()
	{
		_longThrowMode = !_longThrowMode;
	}
	
	public void SetSelectedLimb(string limbName)
	{
		if (Multiplayer.IsServer())
		{
			EmitSignal(SignalName.LimbSelected, limbName);
		}
		else
		{
			RpcId(1, nameof(ServerSetSelectedLimb), _owner.GetMultiplayerAuthority(), limbName);
		}
	}

	private Mob ResolveMobForRpc(int ownerPeerId)
	{
		var senderId = Multiplayer.GetRemoteSenderId();
		if (senderId > 0 && ownerPeerId > 0 && senderId != ownerPeerId)
		{
			GD.PrintErr($"[InteractionComponent] RPC sender mismatch: sender={senderId}, owner={ownerPeerId}");
			return null;
		}

		var resolvedPeerId = senderId > 0 ? senderId : ownerPeerId;
		if (resolvedPeerId <= 0)
			return null;

		var world = GetTree().GetFirstNodeInGroup("World");
		var mob = world?.GetNodeOrNull<Mob>(resolvedPeerId.ToString()) as Mob;
		if (mob != null)
			return mob;

		foreach (var node in GetTree().GetNodesInGroup("Mob"))
		{
			if (node is Mob candidate && candidate.GetMultiplayerAuthority() == resolvedPeerId)
				return candidate;
		}

		return null;
	}
	
	public void Process(double delta)
	{
		if (_throwCooldown > 0)
			_throwCooldown -= (float)delta;
	}
	public void Cleanup() { }
}
