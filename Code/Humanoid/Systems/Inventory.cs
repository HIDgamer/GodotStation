using Godot;
using System.Collections.Generic;

public partial class Inventory : Node, IMobSystem
{
	[Export] public int MaxSlots = 20;
	[Export] public float MaxWeight = 50.0f;
	private const string GrabItemToken = "internal://grab";
	
	private List<ItemStack> _items = new();
	private Dictionary<string, Item> _equipped = new();
	private Mob _owner;
	private Node2D _leftHandSprite;
	private Node2D _rightHandSprite;
	private Node _networkManager;
	private int _activeHand = 0;
	private List<WorldItem> _recentDrops = new();
	
	[Signal] public delegate void InventoryChangedEventHandler();
	
	public override void _Ready()
	{
		_owner = GetParent<Mob>();
		
		_networkManager = GetNodeOrNull("/root/NetworkManager") ??
						GetNodeOrNull("../../NetworkManager") ??
						(GetTree().GetNodesInGroup("NetworkManager").Count > 0 ?
						 GetTree().GetNodesInGroup("NetworkManager")[0] : null);
		
		InitEquipSlots();
		SetupHandSprites();
	}
	
	private void InitEquipSlots()
	{
		_equipped["left_hand"] = null;
		_equipped["right_hand"] = null;
		_equipped["head"] = null;
		_equipped["eyes"] = null;
		_equipped["mask"] = null;
		_equipped["ears_left"] = null;
		_equipped["ears_right"] = null;
		_equipped["gloves"] = null;
		_equipped["uniform"] = null;
		_equipped["armor"] = null;
		_equipped["shoes"] = null;
		_equipped["id"] = null;
		_equipped["belt"] = null;
		_equipped["back"] = null;
		_equipped["pouch_left"] = null;
		_equipped["pouch_right"] = null;
	}
	
	private void SetupHandSprites()
	{
		var spriteSystem = _owner.GetNodeOrNull<Node2D>("SpriteSystem");
		if (spriteSystem == null) return;
		
		_leftHandSprite = spriteSystem.GetNodeOrNull<Node2D>("Left_hand");
		_rightHandSprite = spriteSystem.GetNodeOrNull<Node2D>("Right_hand");
	}
	
	public bool AddItem(Item item, int quantity = 1)
	{
		if (!Multiplayer.IsServer()) return false;
		
		if (item == null || quantity <= 0) return false;
		
		if (item.IsRuntimeUnique)
			item = item.Duplicate(true) as Item ?? item;
		
		var activeSlot = _activeHand == 0 ? "left_hand" : "right_hand";
		var inactiveSlot = _activeHand == 0 ? "right_hand" : "left_hand";
		
		if (_equipped[activeSlot] == null)
		{
			return Equip(item, activeSlot);
		}
		else if (_equipped[inactiveSlot] == null)
		{
			return Equip(item, inactiveSlot);
		}
		
		if (GetTotalWeight() + (item.Weight * quantity) > MaxWeight) return false;
		
		int remaining = quantity;
		
		if (item.MaxStack > 1)
		{
			foreach (var stack in _items)
			{
				if (stack.CanStackWith(new ItemStack(item, 1)))
				{
					remaining = stack.AddQuantity(remaining);
					if (remaining == 0) break;
				}
			}
		}
		
		while (remaining > 0 && _items.Count < MaxSlots)
		{
			int stackSize = Mathf.Min(remaining, item.MaxStack);
			_items.Add(new ItemStack(item, stackSize));
			remaining -= stackSize;
		}
		
		if (remaining < quantity)
		{
			EmitSignal(SignalName.InventoryChanged);
			Rpc(MethodName.SyncInventoryChangeRpc);
			return true;
		}
		return false;
	}
	
public bool Equip(Item item, string slot)
{
	if (!Multiplayer.IsServer()) return false;
	
	if (!_equipped.ContainsKey(slot)) return false;
	if (_equipped[slot] != null) return false;
	
	if (item == null) return false;
	
	_equipped[slot] = item;
		
		UpdateHandSprite(slot);
		EmitSignal(SignalName.InventoryChanged);
		
		string scenePath = GetScenePathForItem(item);
		foreach (var peerId in Multiplayer.GetPeers())
		{
			RpcId(peerId, nameof(SyncEquipRpc), scenePath, slot);
		}
		
		return true;
	}
	
	private string GetScenePathForItem(Item item)
	{
		if (item is GrabItem)
			return GrabItemToken;
		
		// Use ScenePath if explicitly set
		if (!string.IsNullOrEmpty(item.ScenePath))
			return item.ScenePath;
		
		// Fallback for ClothingItems with hardcoded paths
		if (item is ClothingItem)
		{
			return item.ItemName switch
			{
				"Marine_CM_Uniform" => "uid://<UID_OF_MARINE_CM_UNIFORM>",
				"Medical_Scrubs" => "uid://<UID_OF_MEDICAL_SCRUBS>",
				"MA_Light_Armor" => "uid://<UID_OF_MA_LIGHT_ARMOR>",
				"MA_Medium_Armor" => "uid://<UID_OF_MA_MEDIUM_ARMOR>",
				"MA_Heavy_Armor" => "uid://<UID_OF_MA_HEAVY_ARMOR>",
				"Marine_Boots" => "uid://<UID_OF_MARINE_BOOTS>",
				"Combat_Boots" => "uid://<UID_OF_COMBAT_BOOTS>",
				"Marine_Gloves" => "uid://<UID_OF_MARINE_GLOVES>",
				"Armored_Gloves" => "uid://<UID_OF_ARMORED_GLOVES>",
				_ => $"uid://<UID_OF_{item.ItemName.ToUpper()}>"
			};
		}
		
		// Default fallback
		return $"uid://<UID_OF_{item.ItemName.ToUpper()}>";
	}
	
	private bool IsValidClothingSlot(ClothingItem clothing, string slot)
	{
		return clothing.Slot switch
		{
			ClothingItem.ClothingSlot.Head => slot == "head",
			ClothingItem.ClothingSlot.Eyes => slot == "eyes",
			ClothingItem.ClothingSlot.Mask => slot == "mask",
			ClothingItem.ClothingSlot.Ears => slot == "ears_left" || slot == "ears_right",
			ClothingItem.ClothingSlot.Gloves => slot == "gloves",
			ClothingItem.ClothingSlot.Uniform => slot == "uniform",
			ClothingItem.ClothingSlot.Armor => slot == "armor",
			ClothingItem.ClothingSlot.Shoes => slot == "shoes",
			ClothingItem.ClothingSlot.Belt => slot == "belt",
			ClothingItem.ClothingSlot.Back => slot == "back",
			ClothingItem.ClothingSlot.Pouch => slot == "pouch_left" || slot == "pouch_right",
			_ => false
		};
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncEquipRpc(string scenePath, string slot)
	{
		GD.Print($"[Inventory] SyncEquipRpc received: slot={slot}, scene={scenePath}");
		if (scenePath == GrabItemToken)
		{
			_equipped[slot] = new GrabItem();
			CallDeferred(MethodName.EmitSignal, SignalName.InventoryChanged);
			return;
		}
		var scene = GD.Load<PackedScene>(scenePath);
		if (scene != null)
		{
			var tempInstance = scene.Instantiate<WorldItem>();
			_equipped[slot] = tempInstance.ItemData;
			tempInstance.QueueFree();
			CallDeferred(MethodName.EmitSignal, SignalName.InventoryChanged);
		}
	}
	
	public Item Unequip(string slot)
	{
		if (!Multiplayer.IsServer()) return null;
		
		if (!_equipped.ContainsKey(slot)) return null;
		
		var item = _equipped[slot];
		if (item == null) return null;
		
		_equipped[slot] = null;
		UpdateHandSprite(slot);
		EmitSignal(SignalName.InventoryChanged);
		
		foreach (var peerId in Multiplayer.GetPeers())
		{
			RpcId(peerId, nameof(SyncUnequipRpc), slot);
		}
		
		return item;
	}
	
	public void DropEquipped(string slot)
	{
		if (!Multiplayer.IsServer()) return;
		
		var item = GetEquipped(slot);
		if (item == null) return;
		
		Unequip(slot);
		
		var interaction = _owner.GetNodeOrNull<InteractionComponent>("InteractionComponent");
		interaction?.SpawnWorldItem(item, _owner.GlobalPosition);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncUnequipRpc(string slot)
	{
		GD.Print($"[Inventory] SyncUnequipRpc received: slot={slot}");
		_equipped[slot] = null;
		if (slot == "left_hand" || slot == "right_hand")
			UpdateHandSprite(slot);
		CallDeferred(MethodName.EmitSignal, SignalName.InventoryChanged);
	}
	

	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncInventoryChangeRpc()
	{
		EmitSignal(SignalName.InventoryChanged);
	}
	
	private void UpdateHandSprite(string slot)
	{
		if (!Multiplayer.IsServer()) return;
		
		Node2D handSprite = slot == "left_hand" ? _leftHandSprite : 
							slot == "right_hand" ? _rightHandSprite : null;
		
		if (handSprite == null) return;
		
		foreach (var child in handSprite.GetChildren())
		{
			if (child is ItemSpriteSystem)
			{
				handSprite.RemoveChild(child);
				child.QueueFree();
			}
		}
		
		var item = _equipped[slot];
		if (item != null)
		{
			if (item is GrabItem)
				return;
			
			// Get the current direction from the sprite system
			var spriteSystemNode = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
			int currentDirection = spriteSystemNode?.Direction ?? 0;
			
			string scenePath = null;
			
			if (item is ClothingItem)
			{
				scenePath = item.ItemName switch
				{
					"Marine_CM_Uniform" => "uid://<UID_OF_MARINE_CM_UNIFORM>",
					"Medical_Scrubs" => "uid://<UID_OF_MEDICAL_SCRUBS>",
					"MA_Light_Armor" => "uid://<UID_OF_MA_LIGHT_ARMOR>",
					"MA_Medium_Armor" => "uid://<UID_OF_MA_MEDIUM_ARMOR>",
					"MA_Heavy_Armor" => "uid://<UID_OF_MA_HEAVY_ARMOR>",
					"Marine_Boots" => "uid://<UID_OF_MARINE_BOOTS>",
					"Combat_Boots" => "uid://<UID_OF_COMBAT_BOOTS>",
					"Marine_Gloves" => "uid://<UID_OF_MARINE_GLOVES>",
					"Armored_Gloves" => "uid://<UID_OF_ARMORED_GLOVES>",
					_ => null
				};
			}
			else
			{
			scenePath = string.IsNullOrEmpty(item.ScenePath) ? $"uid://<UID_OF_{item.ItemName.ToUpper()}>" : item.ScenePath;
			if (scenePath != null)
			{
				var itemScene = GD.Load<PackedScene>(scenePath);
				if (itemScene != null)
				{
					var instance = itemScene.Instantiate();
					var spriteSystem = instance.GetNodeOrNull<ItemSpriteSystem>("Icon");
					if (spriteSystem != null)
					{
						// Unset owner before moving to prevent "inconsistent owner" warning
						spriteSystem.Owner = null;
						instance.RemoveChild(spriteSystem);
						handSprite.AddChild(spriteSystem);
						spriteSystem.ShowInHand(currentDirection, slot == "left_hand");
						
						// Apply frame settings from item
						ApplyItemFrameSettings(spriteSystem, item);
					}
					instance.QueueFree();
				}
				else
				{
					// Log warning for missing scene file but don't crash
					GD.PrintErr($"[Inventory] Warning: Could not load scene file '{scenePath}' for item '{item.ItemName}'. Using fallback icon.");
					
					// Create a fallback sprite system with just the icon
					var fallbackSpriteSystem = new ItemSpriteSystem();
					fallbackSpriteSystem.IconTexture = item.Icon;
					fallbackSpriteSystem.IconHframes = 1;
					fallbackSpriteSystem.IconVframes = 1;
					fallbackSpriteSystem.DefaultStateId = "default";
					
					// Initialize the fallback sprite system
					fallbackSpriteSystem._Ready();
					
					// Apply frame settings from item
					ApplyItemFrameSettings(fallbackSpriteSystem, item);
					
					handSprite.AddChild(fallbackSpriteSystem);
					fallbackSpriteSystem.ShowIcon();
				}
			}
		}
	}
	}
	private void ApplyItemFrameSettings(ItemSpriteSystem spriteSystem, Item item)
	{
		if (spriteSystem == null || item == null) return;
		
		var iconSprite = spriteSystem.GetIconSprite();
		if (iconSprite != null)
		{
			// Apply frame setting if valid
			if (item.IconFrame >= 0)
			{
				int totalFrames = iconSprite.Hframes * iconSprite.Vframes;
				if (totalFrames > 1)
				{
					iconSprite.Frame = Mathf.Clamp(item.IconFrame, 0, totalFrames - 1);
				}
			}
		}
	}
	
	public Item GetEquipped(string slot) => _equipped.GetValueOrDefault(slot);
	public List<ItemStack> GetAllItems() => new(_items);
	public float GetTotalWeight()
	{
		float weight = 0;
		foreach (var stack in _items)
			weight += stack.ItemData.Weight * stack.Quantity;
		return weight;
	}
	
	public void SetActiveHand(int hand) => _activeHand = hand;
	public int GetActiveHand() => _activeHand;
	
	public void RememberDrop(WorldItem item)
	{
		_recentDrops.Insert(0, item);
		if (_recentDrops.Count > 2)
			_recentDrops.RemoveAt(2);
	}
	
	public bool QuickPickup()
	{
		if (!Multiplayer.IsServer())
		{
			RpcId(1, nameof(RequestQuickPickupRpc), _owner.GetPath());
			return false;
		}
		
		for (int i = 0; i < _recentDrops.Count; i++)
		{
			var item = _recentDrops[i];
			if (!IsInstanceValid(item)) 
			{
				_recentDrops.RemoveAt(i);
				i--;
				continue;
			}
			
			var dist = _owner.GlobalPosition.DistanceTo(item.GlobalPosition);
			if (dist <= 64)
			{
				if (item.TryPickup(_owner))
				{
					_recentDrops.RemoveAt(i);
					return true;
				}
			}
		}
		return false;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestQuickPickupRpc(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNode<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		inventory?.QuickPickup();
	}
	
	public bool TryEquipFromInventory(string slot)
	{
		if (!Multiplayer.IsServer()) return false;
		
		var activeSlot = _activeHand == 0 ? "left_hand" : "right_hand";
		var item = _equipped[activeSlot];
		
		if (item == null) return false;
		
		if (item is ClothingItem clothing && IsValidClothingSlot(clothing, slot))
		{
			if (_equipped[slot] != null) return false;
			
			_equipped[activeSlot] = null;
			_equipped[slot] = item;
			UpdateHandSprite(activeSlot);
			EmitSignal(SignalName.InventoryChanged);
			
			string scenePath = GetScenePathForItem(item);
			foreach (var peerId in Multiplayer.GetPeers())
			{
				RpcId(peerId, nameof(SyncUnequipRpc), activeSlot);
				RpcId(peerId, nameof(SyncEquipRpc), scenePath, slot);
			}
			
			return true;
		}
		
		return false;
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestUnequipToHandRpc(NodePath mobPath, string fromSlot, string toSlot)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNodeOrNull<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		if (inventory == null) return;
		
		var item = inventory.GetEquipped(fromSlot);
		if (item != null && inventory.GetEquipped(toSlot) == null)
		{
			inventory.Unequip(fromSlot);
			inventory.Equip(item, toSlot);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestEquipFromHandRpc(NodePath mobPath, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNodeOrNull<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		inventory?.TryEquipFromInventory(slot);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestDropEquippedRpc(NodePath mobPath, string slot)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNodeOrNull<Mob>(mobPath);
		var inventory = mob?.GetNodeOrNull<Inventory>("Inventory");
		inventory?.DropEquipped(slot);
	}
	
	/// <summary>
	/// Swaps items between two equipment slots
	/// </summary>
	/// <param name="slot1">First slot name</param>
	/// <param name="slot2">Second slot name</param>
	/// <returns>True if swap was successful</returns>
	public bool SwapItems(string slot1, string slot2)
	{
		if (!Multiplayer.IsServer()) return false;
		
		if (!_equipped.ContainsKey(slot1) || !_equipped.ContainsKey(slot2))
			return false;
		
		var item1 = _equipped[slot1];
		var item2 = _equipped[slot2];
		
		// Unequip both items
		_equipped[slot1] = null;
		_equipped[slot2] = null;
		
		// Update sprites for both slots
		UpdateHandSprite(slot1);
		UpdateHandSprite(slot2);
		
		// Equip items in swapped positions
		if (item1 != null)
			Equip(item1, slot2);
		if (item2 != null)
			Equip(item2, slot1);
		
		EmitSignal(SignalName.InventoryChanged);
		
		// Sync with all peers
		foreach (var peerId in Multiplayer.GetPeers())
		{
			RpcId(peerId, nameof(SyncInventoryChangeRpc));
		}
		
		return true;
	}
	
	public void Init(Mob mob) { }
	public void Process(double delta) { }
	public void Cleanup() { _items.Clear(); }
}
