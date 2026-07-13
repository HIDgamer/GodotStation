using Godot;
using System.Collections.Generic;

public partial class ClothingManager : Node2D, IMobSystem
{
	private Mob _owner;
	private Inventory _inventory;
	private Dictionary<string, Sprite2D> _clothingSprites = new();
	private int _lastDirection = -1;
	
	public void Init(Mob mob)
	{
		_owner = mob;
		_inventory = mob.GetNodeOrNull<Inventory>("Inventory");
		
		if (_inventory != null)
			_inventory.InventoryChanged += UpdateClothingSprites;
		
		InitializeSprites();
		
		if (!Multiplayer.IsServer())
		{
			CallDeferred(nameof(RequestClothingSyncRpc), mob.GetPath());
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestClothingSyncRpc(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		
		var mob = GetNodeOrNull<Mob>(mobPath);
		var clothingMgr = mob?.GetNodeOrNull<ClothingManager>("ClothingManager");
		if (clothingMgr != null)
		{
			var senderId = Multiplayer.GetRemoteSenderId();
			clothingMgr.SyncAllClothingToClient(senderId);
		}
	}
	
	private void InitializeSprites()
	{
		var spriteSystem = _owner.GetNodeOrNull<Node2D>("SpriteSystem");
		if (spriteSystem == null) return;
		
		_clothingSprites["uniform"] = CreateClothingSprite("Uniform", -1);
		_clothingSprites["shoes"] = CreateClothingSprite("Shoes", -2);
		_clothingSprites["gloves"] = CreateClothingSprite("Gloves", 1);
		_clothingSprites["armor"] = CreateClothingSprite("Armor", 2);
		_clothingSprites["belt"] = CreateClothingSprite("Belt", 3);
		_clothingSprites["back"] = CreateClothingSprite("Back", -3);
		_clothingSprites["mask"] = CreateClothingSprite("Mask", 4);
		_clothingSprites["eyes"] = CreateClothingSprite("Eyes", 5);
		_clothingSprites["head"] = CreateClothingSprite("Head", 6);
		
		foreach (var sprite in _clothingSprites.Values)
			spriteSystem.AddChild(sprite);
	}
	
	private Sprite2D CreateClothingSprite(string name, int zIndex)
	{
		return new Sprite2D
		{
			Name = name,
			ZIndex = zIndex,
			Hframes = 4,
			Vframes = 1,
			Visible = false,
			Centered = true
		};
	}
	
	private void UpdateClothingSprites()
	{
		if (_inventory == null) return;
		
		UpdateSlotSprite("uniform", _inventory.GetEquipped("uniform"));
		UpdateSlotSprite("shoes", _inventory.GetEquipped("shoes"));
		UpdateSlotSprite("gloves", _inventory.GetEquipped("gloves"));
		UpdateSlotSprite("armor", _inventory.GetEquipped("armor"));
		UpdateSlotSprite("belt", _inventory.GetEquipped("belt"));
		UpdateSlotSprite("back", _inventory.GetEquipped("back"));
		UpdateSlotSprite("mask", _inventory.GetEquipped("mask"));
		UpdateSlotSprite("eyes", _inventory.GetEquipped("eyes"));
		UpdateSlotSprite("head", _inventory.GetEquipped("head"));
		
		if (Multiplayer.IsServer())
		{
			foreach (var peerId in Multiplayer.GetPeers())
			{
				SyncAllClothingToClient(peerId);
			}
		}
	}
	
	private void SyncAllClothingToClient(long peerId)
	{
		if (_inventory == null) return;
		
		var slots = new[] { "uniform", "shoes", "gloves", "armor", "belt", "back", "mask", "eyes", "head" };
		foreach (var slot in slots)
		{
			var item = _inventory.GetEquipped(slot);
			if (item is ClothingItem clothing && clothing.WornTexture != null)
			{
				string texturePath = clothing.WornTexture.ResourcePath;
				if (texturePath.Contains("::"))
					texturePath = texturePath.Split("::")[0];
				RpcId(peerId, nameof(SyncClothingSpriteRpc), slot, texturePath);
			}
			else
			{
				RpcId(peerId, nameof(SyncClothingSpriteRpc), slot, "");
			}
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncClothingSpriteRpc(string slot, string texturePath)
	{
		if (!_clothingSprites.ContainsKey(slot)) return;
		
		var sprite = _clothingSprites[slot];
		
		if (!string.IsNullOrEmpty(texturePath))
		{
			sprite.Texture = GD.Load<Texture2D>(texturePath);
			sprite.Visible = true;
		}
		else
		{
			sprite.Visible = false;
		}
	}
	
	private void UpdateSlotSprite(string slot, Item item)
	{
		if (!_clothingSprites.ContainsKey(slot)) return;
		
		var sprite = _clothingSprites[slot];
		
		if (item is ClothingItem clothing && clothing.WornTexture != null)
		{
			sprite.Texture = clothing.WornTexture;
			sprite.Frame = GetDirectionFrame();
			sprite.Visible = true;
		}
		else
		{
			sprite.Visible = false;
		}
	}
	
	public Dictionary<string, float> GetTotalArmor()
	{
		var armor = new Dictionary<string, float>
		{
			["melee"] = 0f,
			["bullet"] = 0f,
			["laser"] = 0f,
			["bomb"] = 0f,
			["bio"] = 0f,
			["rad"] = 0f,
			["fire"] = 0f,
			["acid"] = 0f
		};
		
		if (_inventory == null) return armor;
		
		foreach (var slot in new[] { "uniform", "shoes", "gloves", "armor", "head", "mask", "eyes" })
		{
			if (_inventory.GetEquipped(slot) is ClothingItem clothing)
			{
				armor["melee"] += clothing.ArmorMelee;
				armor["bullet"] += clothing.ArmorBullet;
				armor["laser"] += clothing.ArmorLaser;
				armor["bomb"] += clothing.ArmorBomb;
				armor["bio"] += clothing.ArmorBio;
				armor["rad"] += clothing.ArmorRad;
				armor["fire"] += clothing.ArmorFire;
				armor["acid"] += clothing.ArmorAcid;
			}
		}
		
		return armor;
	}
	
	public float GetSpeedModifier()
	{
		float modifier = 0f;
		if (_inventory == null) return modifier;
		
		foreach (var slot in new[] { "uniform", "shoes", "armor", "back" })
		{
			if (_inventory.GetEquipped(slot) is ClothingItem clothing)
				modifier += clothing.SpeedModifier;
		}
		
		return modifier;
	}
	
	public void Process(double delta)
	{
		SyncOrientation();
	}

	private void SyncOrientation()
	{
		var spriteSystem = _owner?.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		if (spriteSystem == null) return;

		var direction = spriteSystem.Direction;
		var bodyRotation = spriteSystem.GetNodeOrNull<Sprite2D>("Body")?.Rotation ?? 0.0f;
		if (_lastDirection == direction)
		{
			foreach (var sprite in _clothingSprites.Values)
			{
				if (sprite.Visible)
					sprite.Rotation = bodyRotation;
			}
			return;
		}

		_lastDirection = direction;
		var frame = DirectionToFrame(direction);
		foreach (var sprite in _clothingSprites.Values)
		{
			if (!sprite.Visible) continue;
			sprite.Frame = frame;
			sprite.Rotation = bodyRotation;
		}
	}

	private int GetDirectionFrame()
	{
		var spriteSystem = _owner?.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		return DirectionToFrame(spriteSystem?.Direction ?? 0);
	}

	private static int DirectionToFrame(int direction)
	{
		return Mathf.Clamp(direction, 0, 3);
	}
	
	public void Cleanup()
	{
		if (_inventory != null)
			_inventory.InventoryChanged -= UpdateClothingSprites;
	}
}
