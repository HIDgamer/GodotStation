using Godot;

public partial class InteractionComponent : Node, IMobSystem
{
	private Mob _owner;
	private Inventory _inventory;
	private int _activeHand;
	private bool _throwMode;
	private WeaponHandlingComponent _weaponHandling;
	
	[Signal] public delegate void HandSwitchedEventHandler(int hand);
	
	public void Init(Mob mob)
	{
		_owner = mob;
		_inventory = mob.GetNodeOrNull<Inventory>("Inventory");
		_weaponHandling = mob.GetNodeOrNull<WeaponHandlingComponent>("WeaponHandlingComponent");
		if (_inventory != null)
			_activeHand = _inventory.GetActiveHand();
	}
	
	public override void _Input(InputEvent @event)
	{
		if (!_owner.IsMultiplayerAuthority()) return;
		
		var state = _owner.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (state != null && state.GetState() != MobState.Standing)
			return;
		
		if (@event.IsActionPressed("switch_hand"))
		{
			SwitchHands();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("drop"))
		{
			DropActive();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("throw_toggle"))
		{
			if (@event is InputEventKey keyEvent && keyEvent.ShiftPressed)
				return;
			_throwMode = !_throwMode;
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("activate"))
		{
			ActivateHeld();
			GetViewport().SetInputAsHandled();
		}
		else if (@event.IsActionPressed("quick_pickup"))
		{
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
			RpcId(1, nameof(ServerSwapHand), _owner.GetPath());
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
			RpcId(1, nameof(ServerDropItem), _owner.GetPath(), slot, _owner.GlobalPosition);
		}
	}
	
	public void ThrowActive(Vector2 targetPos)
	{
		if (_inventory == null || !_throwMode) return;
		
		var slot = _activeHand == 0 ? "left_hand" : "right_hand";
		var item = _inventory.GetEquipped(slot);
		if (item == null) return;
		
		if (Multiplayer.IsServer())
		{
			_inventory.Unequip(slot);
			ThrowWorldItem(item, _owner.GlobalPosition, targetPos);
			_throwMode = false;
		}
		else
		{
			RpcId(1, nameof(ServerThrowItem), _owner.GetPath(), slot, _owner.GlobalPosition, targetPos);
			_throwMode = false;
		}
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
				RpcId(1, nameof(ServerActivate), _owner.GetPath(), slot);
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
				RpcId(1, nameof(ServerActivate), _owner.GetPath(), slot);
			}
		}
		else if (item is ClothingItem clothing)
		{
			if (Multiplayer.IsServer())
				_inventory.TryEquipFromInventory(GetClothingSlot(clothing));
			else
				RpcId(1, nameof(ServerActivate), _owner.GetPath(), slot);
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
	private void ServerSwapHand(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		GetNodeOrNull<Mob>(mobPath)?.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.SwitchHands();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncHandSwap()
	{
		SwapHandLocal();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerDropItem(NodePath mobPath, string slot, Vector2 position)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNode<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null)
		{
			inventory.Unequip(slot);
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.SpawnWorldItem(item, position);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerThrowItem(NodePath mobPath, string slot, Vector2 spawnPos, Vector2 targetPos)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNode<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var item = inventory?.GetEquipped(slot);
		
		if (item != null)
		{
			inventory.Unequip(slot);
			mob.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.ThrowWorldItem(item, spawnPos, targetPos);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerActivate(NodePath mobPath, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		GetNodeOrNull<Mob>(mobPath)?.GetNodeOrNull<InteractionComponent>("InteractionComponent")?.ActivateHeld();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerActivateGrab(int ownerPeerId)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var mob = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem")?.HandleActivate();
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerReleaseGrab(int ownerPeerId, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		var world = GetTree().GetFirstNodeInGroup("World");
		var mob = world?.GetNodeOrNull(ownerPeerId.ToString()) as Mob;
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		var interactionSystem = mob?.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		
		if (inventory != null && interactionSystem != null)
		{
			inventory.Unequip(slot);
			interactionSystem.StopPull();
		}
	}
	
	public int GetActiveHand() => _activeHand;
	public bool IsThrowMode() => _throwMode;
	
	public void Process(double delta) { }
	public void Cleanup() { }
}
