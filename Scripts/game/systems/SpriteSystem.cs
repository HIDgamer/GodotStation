using Godot;
using System.Collections.Generic;

public partial class SpriteSystem : Node2D
{
	[Export] public int Direction { get; set; } = 0;
	[Export] public string State { get; set; } = "idle";
	[Export] public string Ethnicity { get; set; } = "Western";
	[Export] public string Gender { get; set; } = "Male";
	[Export] public bool ShowGear { get; set; } = true;
	[Export] public string EyeColor { get; set; } = "#000000";
	[Export] public string HairBaseColor { get; set; } = "#000000";
	[Export] public float HeadTurnSpeed { get; set; } = 0.15f;
	[Export] public bool IsPreviewMode { get; set; } = false;
	[Export] public bool EnableNormalMaps { get; set; } = false; // Disable normal maps to save VRAM
	[Export] public bool EnableTextureCompression { get; set; } = true; // Enable texture compression

	private Node _preferenceManager;
	private readonly Dictionary<string, Texture2D> _textureCache = new();
	private readonly Dictionary<string, CanvasTexture> _canvasTextureCache = new(); // Cache complete CanvasTextures
	private const int MaxCacheSize = 25; // Reduced cache size to save memory
	private ProfilingManager _profilingManager;
	private readonly int[] _frameMap = { 0, 1, 2, 3 };
	private Vector2 _mouseTarget;
	private bool _hasMouseTarget;
	private int _headFrame = 0;
	private bool _isPeeking = false;
	private bool _isProne = false;
	
	private int _targetHeadFrame = 0;
	private float _headTurnTimer = 0f;
	private Queue<int> _headFramePath = new Queue<int>();
	private Tween _thrustTween;
	private Tween _doAfterTween;

	private readonly string[] _bodyParts = {
		"Left_foot", "Right_foot", "Left_leg", "Right_leg",
		"Body", "Left_arm", "Right_arm", "Head",
		"Left_hand", "Right_hand", "Eyes", "Hair", "Facial_Hair", "Underwear", "Undershirt"
	};
	
	private readonly string[] _gearParts = {
		"Uniform", "Shoes", "Gloves", "Armor", "Belt", "Back", "Mask", "Eyes_Gear", "Head_Gear"
	};

	private const string BaseRacePath = "res://Assets/Human/Race/";
	private const string BaseBodyHairPath = "res://Assets/Human/BodyHair/";
	private const string BaseClothingPath = "res://Assets/Human/Clothing/";

	public override void _Ready()
	{
		if (!IsPreviewMode)
		{
			var parent = GetParent();
			if (parent != null)
			{
				string parentName = parent.Name.ToString();
				if (parentName.Contains("CharacterBackground") || parentName.Contains("Preview"))
					IsPreviewMode = true;
			}
		}
		
		_preferenceManager = GetNodeOrNull("/root/PreferenceManager") ?? 
							GetNodeOrNull("../../PreferenceManager") ??
							(GetTree().GetNodesInGroup("PreferenceManager").Count > 0 ? 
							 GetTree().GetNodesInGroup("PreferenceManager")[0] : null);

		_profilingManager = GetNodeOrNull<ProfilingManager>("/root/ProfilingManager");

		if (_preferenceManager != null)
		{
			_preferenceManager.Connect("character_data_changed", Callable.From(ReloadAppearance));
		}

		InitializeGearSprites();
		ApplyTextures();
		_headFrame = Direction;
		_targetHeadFrame = Direction;
		ReloadAppearance();
		
		var parent2 = GetParent();
		if (parent2 is Mob mob)
		{
			var inventory = mob.GetNodeOrNull<Inventory>("Inventory");
			if (inventory != null)
				inventory.InventoryChanged += UpdateClothingSprites;
		}
	}

	private void InitializeGearSprites()
	{
		foreach (var part in _gearParts)
		{
			var sprite = GetNodeOrNull<Sprite2D>(part);
			if (sprite == null)
			{
				sprite = new Sprite2D { Name = part };
				AddChild(sprite);
			}
			sprite.Visible = false;
		}
	}

	private void ApplyTextures()
	{
		var data = GetCharacterData();
		
		if (data.Count > 0)
		{
			Ethnicity = (string)data.GetValueOrDefault("race", "Western");
			Gender = (string)data.GetValueOrDefault("gender", "Male");
			EyeColor = (string)data.GetValueOrDefault("eye_color", "#000000");
			HairBaseColor = (string)data.GetValueOrDefault("hair_base_color", "#000000");
		}

		foreach (var part in _bodyParts)
		{
			var sprite = GetNodeOrNull<Sprite2D>(part) ?? new Sprite2D { Name = part };
			if (sprite.GetParent() == null)
				AddChild(sprite);

			string partName = GetPartName(part, data);
			
			if (string.IsNullOrEmpty(partName))
			{
				sprite.Visible = false;
				continue;
			}

			var diffuseTexture = LoadTexture(partName, "base");
			if (diffuseTexture != null)
			{
				// Check if we have a cached canvastexture for this part.
				string canvasCacheKey = $"{partName}_canvas";
				CanvasTexture canvasTexture;
				
				if (_canvasTextureCache.TryGetValue(canvasCacheKey, out var cachedCanvas))
				{
					canvasTexture = cachedCanvas;
				}
				else
				{
					// Create new canvastexture with optional normal map.
					canvasTexture = new CanvasTexture
					{
						DiffuseTexture = diffuseTexture,
						NormalTexture = EnableNormalMaps ? LoadTexture(partName, "normal") : null
					};
					
					// Cache it if we have room.
					if (_canvasTextureCache.Count < MaxCacheSize)
					{
						_canvasTextureCache[canvasCacheKey] = canvasTexture;
					}
				}

				sprite.Texture = canvasTexture;
				sprite.Hframes = 4;
				sprite.Vframes = 1;
				sprite.Frame = _frameMap[Direction];
				
				bool isGear = part is "Left_arm" or "Right_arm" or "Left_hand" or "Right_hand";
				sprite.Visible = ShowGear || !isGear;

				sprite.Modulate = part switch
				{
					"Eyes" => new Color(EyeColor),
					"Hair" or "Facial_Hair" => new Color(HairBaseColor),
					_ => Colors.White
				};
			}
			else
			{
				sprite.Visible = false;
			}
		}
		
		SyncInHandSpriteFrames();
	}

	public void apply_textures()
	{
		ApplyTextures();
	}

	private Texture2D LoadTexture(string partName, string type)
	{
		string cacheKey = $"{partName}_{type}";
		
		if (_textureCache.TryGetValue(cacheKey, out Texture2D cachedTexture))
			return cachedTexture;

		if (_textureCache.Count >= MaxCacheSize)
			_textureCache.Clear();

		string resPath = BuildTexturePath(partName, type);
		
		Texture2D texture = null;
		
		if (ResourceLoader.Exists(resPath))
		{
			texture = ResourceLoader.Load<Texture2D>(resPath);
		}

		if (texture != null)
		{
			_textureCache[cacheKey] = texture;
			
			// Track texture memory usage.
			if (_profilingManager != null)
			{
				var textureSize = texture.GetSize();
				float estimatedMemory = (textureSize.X * textureSize.Y * 4) / (1024.0f * 1024.0f); // RGBA8 = 4 bytes per pixel
				_profilingManager.AddResourceUsage("TextureMemory", estimatedMemory, "MB");
			}
		}
		
		return texture;
	}

	private string BuildTexturePath(string partName, string type)
	{
		string basePath = GetBasePath(partName);
		string suffix = type switch
		{
			"normal" => "_n",
			"specular" => "_s",
			_ => ""
		};
		return $"{basePath}{partName}{suffix}.png";
	}

	private string GetBasePath(string partName)
	{
		if (partName.StartsWith("Underwear")) return $"{BaseClothingPath}UnderWear/";
		if (partName.StartsWith("UnderShirt")) return $"{BaseClothingPath}UnderShirt/";
		if (partName.StartsWith("Facial")) return $"{BaseBodyHairPath}FacialHair/";
		if (partName.StartsWith("Hair") && partName.Length > 4) return $"{BaseBodyHairPath}Hair/";
		
		return $"{BaseRacePath}{Ethnicity}/";
	}

	private string GetPartName(string part, Godot.Collections.Dictionary data)
	{
		string gender = (string)data.GetValueOrDefault("gender", "Male");

		string partName = part switch
		{
			"Hair" => GetHairPartName(data),
			"Facial_Hair" => GetFacialHairPartName(data, gender),
			"Underwear" => GetUnderwearPartName(data),
			"Undershirt" => GetUndershirtPartName(data, gender),
			"Body" or "Head" or "Left_arm" or "Right_arm" or "Left_leg" or "Right_leg" or 
			"Left_foot" or "Right_foot" or "Left_hand" or "Right_hand" 
				=> gender == "Female" ? $"{part}_Female" : part,
			_ => part
		};
		
		return partName;
	}

	private string GetHairPartName(Godot.Collections.Dictionary data)
	{
		string hairStyle = (string)data.GetValueOrDefault("hair_style", "");
		if (string.IsNullOrEmpty(hairStyle) || hairStyle == "Default")
			return "";
		
		string hairPath = $"{BaseBodyHairPath}Hair/Hair{hairStyle}.png";
		if (!ResourceLoader.Exists(hairPath))
			return "";
		
		return $"Hair{hairStyle}";
	}

	private string GetFacialHairPartName(Godot.Collections.Dictionary data, string gender)
	{
		if (gender == "Female")
			return "";
		
		string facialStyle = (string)data.GetValueOrDefault("facial_hair_style", "");
		if (string.IsNullOrEmpty(facialStyle))
			return "";
		
		string facialPath = $"{BaseBodyHairPath}FacialHair/Facial{facialStyle}.png";
		if (!ResourceLoader.Exists(facialPath))
			return "";
		
		return $"Facial{facialStyle}";
	}

	private string GetUnderwearPartName(Godot.Collections.Dictionary data)
	{
		string underwearStyle = (string)data.GetValueOrDefault("underwear_style", "1");
		if (string.IsNullOrEmpty(underwearStyle))
			return "";
		
		string underwearPath = $"{BaseClothingPath}UnderWear/Underwear_{underwearStyle}.png";
		if (!ResourceLoader.Exists(underwearPath))
			return "";
		
		return $"Underwear_{underwearStyle}";
	}

	private string GetUndershirtPartName(Godot.Collections.Dictionary data, string gender)
	{
		string undershirtStyle = (string)data.GetValueOrDefault("undershirt_style", "");
		if (string.IsNullOrEmpty(undershirtStyle))
			undershirtStyle = gender == "Female" ? "1" : "";
		
		if (string.IsNullOrEmpty(undershirtStyle))
			return "";
		
		string undershirtPath = $"{BaseClothingPath}UnderShirt/UnderShirt_{undershirtStyle}.png";
		if (!ResourceLoader.Exists(undershirtPath))
			return "";
		
		return $"UnderShirt_{undershirtStyle}";
	}

	private Godot.Collections.Dictionary GetCharacterData()
	{
		if (IsPreviewMode)
		{
			if (_preferenceManager != null)
			{
				var data = (Godot.Collections.Dictionary)_preferenceManager.Call("get_character_data");
				return data;
			}
			return new Godot.Collections.Dictionary();
		}

		var parent = GetParent();
		if (parent != null && int.TryParse(parent.Name, out int peerId))
		{
			if (_preferenceManager == null)
			{
				_preferenceManager = GetNodeOrNull("/root/PreferenceManager");
				if (_preferenceManager == null)
				{
					return new Godot.Collections.Dictionary();
				}
			}
			
			var peerData = (Godot.Collections.Dictionary)_preferenceManager.Call("get_peer_character_data", peerId);
			if (peerData != null && peerData.Count > 0)
				return peerData;
		}

		return new Godot.Collections.Dictionary();
	}

	public void ReloadAppearance()
	{
		_preferenceManager = GetNodeOrNull("/root/PreferenceManager");
		_textureCache.Clear();
		ApplyTextures();
	}

	public void ApplyAppearanceWithData(Godot.Collections.Dictionary data)
	{
		if (data.Count > 0)
		{
			Ethnicity = (string)data.GetValueOrDefault("race", "Western");
			Gender = (string)data.GetValueOrDefault("gender", "Male");
			EyeColor = (string)data.GetValueOrDefault("eye_color", "#000000");
			HairBaseColor = (string)data.GetValueOrDefault("hair_base_color", "#000000");
		}
		_textureCache.Clear();
		ApplyTextures();
	}

	public void SetDirection(int direction)
	{
		if (Direction != direction)
		{
			Direction = direction;
			ApplyTextures();
			SyncInHandSpriteFrames();
			UpdateClothingSprites();
		}
	}
	
	private void SyncInHandSpriteFrames()
	{
		var leftHandNode = GetNodeOrNull<Node2D>("Left_hand");
		if (leftHandNode != null)
		{
			var itemSpriteSystem = leftHandNode.GetNodeOrNull<ItemSpriteSystem>("Icon");
			if (itemSpriteSystem != null)
			{
				itemSpriteSystem.SyncInHandFrame(_frameMap[Direction]);
			}
		}
		
		var rightHandNode = GetNodeOrNull<Node2D>("Right_hand");
		if (rightHandNode != null)
		{
			var itemSpriteSystem = rightHandNode.GetNodeOrNull<ItemSpriteSystem>("Icon");
			if (itemSpriteSystem != null)
			{
				itemSpriteSystem.SyncInHandFrame(_frameMap[Direction]);
			}
		}
	}
	
	public void SetState(string state)
	{
		State = state;
	}

	public void SetGender(string gender)
	{
		if (Gender != gender)
		{
			Gender = gender;
			_textureCache.Clear();
			ApplyTextures();
		}
	}

	public void SetEthnicity(string ethnicity)
	{
		if (Ethnicity != ethnicity)
		{
			Ethnicity = ethnicity;
			_textureCache.Clear();
			ApplyTextures();
		}
	}

	public void SetEyeColor(string eyeColor)
	{
		EyeColor = eyeColor;
		ApplyTextures();
	}

	public void SetHairBaseColor(string hairColor)
	{
		HairBaseColor = hairColor;
		ApplyTextures();
	}

	public int GetDirection()
	{
		return Direction;
	}

	public void PlayThrustTween(Vector2 direction)
	{
		_thrustTween?.Kill();
		_thrustTween = CreateTween();
		Vector2 offset = direction.Normalized() * 4;
		_thrustTween.TweenProperty(this, "position", Position + offset, 0.1);
		_thrustTween.TweenProperty(this, "position", Position, 0.1);
	}

	public void SetPeeking(bool isPeeking)
	{
		_isPeeking = isPeeking;
		
		if (!isPeeking)
		{
			_hasMouseTarget = false;
			_headFrame = Direction;
			_targetHeadFrame = Direction;
			_headFramePath.Clear();
			UpdateHeadSpritesLocal();
		}
	}

	public void SetPeekingState(bool isPeeking, Vector2 mouseTarget)
	{
		_isPeeking = isPeeking;
		
		if (isPeeking)
		{
			_hasMouseTarget = true;
			_mouseTarget = mouseTarget;
		}
		else
		{
			_isPeeking = false;
			_hasMouseTarget = false;
			_headFrame = Direction;
			_targetHeadFrame = Direction;
			_headFramePath.Clear();
			UpdateHeadSpritesLocal();
		}
	}

	public void SetHeadFrame(int headFrame)
	{
		_headFrame = headFrame;
		UpdateHeadSpritesLocal();
	}

	public bool GetIsPeeking() => _isPeeking;
	public Vector2 GetMouseTarget() => _mouseTarget;

	public void SetMouseTarget(Vector2 target)
	{
		if (_isPeeking)
		{
			_mouseTarget = target;
			_hasMouseTarget = true;
		}
	}

	public override void _Process(double delta)
	{
		if (_isPeeking && _hasMouseTarget)
		{
			UpdateHeadDirection((float)delta);
			
			var parent = GetParent();
			if (parent != null && int.TryParse(parent.Name, out int peerId))
			{
				if (parent is Node2D node && node.IsMultiplayerAuthority())
				{
					var networkManager = GetNodeOrNull("/root/NetworkManager");
					networkManager?.Call("SyncHeadFrame", peerId, _headFrame);
				}
			}
		}
	}

	private void UpdateHeadDirection(float delta)
	{
		float dx = _mouseTarget.X - GlobalPosition.X;
		float dy = _mouseTarget.Y - GlobalPosition.Y;
		
		int desiredFrame;
		if (Mathf.Abs(dx) > Mathf.Abs(dy))
			desiredFrame = dx > 0 ? 2 : 3;
		else
			desiredFrame = dy > 0 ? 0 : 1;
		
		int[] opposites = { 1, 0, 3, 2 };
		if (desiredFrame == opposites[Direction])
			desiredFrame = FindBestAllowedDirection(dx, dy);
		
		if (_targetHeadFrame != desiredFrame)
		{
			_targetHeadFrame = desiredFrame;
			CalculateHeadPath();
		}
		
		if (_headFramePath.Count > 0)
		{
			_headTurnTimer += delta;
			
			if (_headTurnTimer >= HeadTurnSpeed)
			{
				_headTurnTimer = 0f;
				_headFrame = _headFramePath.Dequeue();
				UpdateHeadSprites();
				UpdateZLevels(_headFrame);
			}
		}
	}

	private int FindBestAllowedDirection(float dx, float dy)
	{
		int[] opposites = { 1, 0, 3, 2 };
		int forbidden = opposites[Direction];
		
		Dictionary<int, float> scores = new Dictionary<int, float>();
		
		for (int dir = 0; dir < 4; dir++)
		{
			if (dir == forbidden) continue;
			
			float score = dir switch
			{
				0 => dy,
				1 => -dy,
				2 => dx,
				3 => -dx,
				_ => 0
			};
			
			scores[dir] = score;
		}
		
		int bestDir = Direction;
		float bestScore = float.MinValue;
		
		foreach (var kvp in scores)
		{
			if (kvp.Value > bestScore)
			{
				bestScore = kvp.Value;
				bestDir = kvp.Key;
			}
		}
		
		return bestDir;
	}

	private void CalculateHeadPath()
	{
		_headFramePath.Clear();
		
		if (_headFrame == _targetHeadFrame)
			return;
		
		int current = _headFrame;
		int target = _targetHeadFrame;
		
		int[] opposites = { 1, 0, 3, 2 };
		if (target == opposites[Direction])
			return;
		
		bool isOpposite = (current == 0 && target == 1) || (current == 1 && target == 0) ||
						  (current == 2 && target == 3) || (current == 3 && target == 2);
		
		if (isOpposite)
		{
			int intermediate = ChooseSafeIntermediate(current, target);
			_headFramePath.Enqueue(intermediate);
			_headFramePath.Enqueue(target);
		}
		else
		{
			_headFramePath.Enqueue(target);
		}
	}

	private int ChooseSafeIntermediate(int current, int target)
	{
		int[] opposites = { 1, 0, 3, 2 };
		int forbidden = opposites[Direction];
		
		List<int> possibleIntermediates = new List<int>();
		
		if ((current == 0 || current == 1) && (target == 0 || target == 1))
		{
			possibleIntermediates.Add(2);
			possibleIntermediates.Add(3);
		}
		else if ((current == 2 || current == 3) && (target == 2 || target == 3))
		{
			possibleIntermediates.Add(0);
			possibleIntermediates.Add(1);
		}
		
		possibleIntermediates.RemoveAll(dir => dir == forbidden);
		
		if (possibleIntermediates.Count > 0)
		{
			float dx = _mouseTarget.X - GlobalPosition.X;
			float dy = _mouseTarget.Y - GlobalPosition.Y;
			
			int best = possibleIntermediates[0];
			float bestScore = float.MinValue;
			
			foreach (int dir in possibleIntermediates)
			{
				float score = dir switch
				{
					0 => dy,
					1 => -dy,
					2 => dx,
					3 => -dx,
					_ => 0
				};
				
				if (score > bestScore)
				{
					bestScore = score;
					best = dir;
				}
			}
			
			return best;
		}
		
		return Direction;
	}

	private void UpdateClothingSprites()
	{
		var parent = GetParent();
		if (parent is not Mob mob) return;
		
		var inventory = mob.GetNodeOrNull<Inventory>("Inventory");
		if (inventory == null) return;
		
		UpdateClothingSlot("Uniform", inventory.GetEquipped("uniform"));
		UpdateClothingSlot("Shoes", inventory.GetEquipped("shoes"));
		UpdateClothingSlot("Gloves", inventory.GetEquipped("gloves"));
		UpdateClothingSlot("Armor", inventory.GetEquipped("armor"));
		UpdateClothingSlot("Belt", inventory.GetEquipped("belt"));
		UpdateClothingSlot("Back", inventory.GetEquipped("back"));
		UpdateClothingSlot("Mask", inventory.GetEquipped("mask"));
		UpdateClothingSlot("Eyes_Gear", inventory.GetEquipped("eyes"));
		UpdateClothingSlot("Head_Gear", inventory.GetEquipped("head"));
	}
	
	private void UpdateClothingSlot(string slotName, Item item)
	{
		var sprite = GetNodeOrNull<Sprite2D>(slotName);
		if (sprite == null)
		{
			sprite = new Sprite2D { Name = slotName };
			AddChild(sprite);
		}
		
		if (item is ClothingItem clothing && clothing.WornTexture != null)
		{
			sprite.Texture = clothing.WornTexture;
			sprite.Hframes = 4;
			sprite.Vframes = 1;
			sprite.Frame = _frameMap[Direction];
			sprite.Visible = true;
		}
		else
		{
			sprite.Visible = false;
		}
	}

	private void UpdateHeadSprites()
	{
		var headSprite = GetNodeOrNull<Sprite2D>("Head");
		var hairSprite = GetNodeOrNull<Sprite2D>("Hair");
		var eyesSprite = GetNodeOrNull<Sprite2D>("Eyes");
		var facialHairSprite = GetNodeOrNull<Sprite2D>("Facial_Hair");
		
		if (headSprite != null && headSprite.Texture != null)
			headSprite.Frame = _headFrame;
		if (hairSprite != null && hairSprite.Texture != null)
			hairSprite.Frame = _headFrame;
		if (eyesSprite != null && eyesSprite.Texture != null)
			eyesSprite.Frame = _headFrame;
		if (facialHairSprite != null && facialHairSprite.Texture != null && facialHairSprite.Visible)
			facialHairSprite.Frame = _headFrame;
	}

	private void UpdateHeadSpritesLocal()
	{
		var headSprite = GetNodeOrNull<Sprite2D>("Head");
		var hairSprite = GetNodeOrNull<Sprite2D>("Hair");
		var eyesSprite = GetNodeOrNull<Sprite2D>("Eyes");
		var facialHairSprite = GetNodeOrNull<Sprite2D>("Facial_Hair");
		
		if (headSprite != null && headSprite.Texture != null)
			headSprite.Frame = _headFrame;
		if (hairSprite != null && hairSprite.Texture != null)
			hairSprite.Frame = _headFrame;
		if (eyesSprite != null && eyesSprite.Texture != null)
			eyesSprite.Frame = _headFrame;
		if (facialHairSprite != null && facialHairSprite.Texture != null && facialHairSprite.Visible)
			facialHairSprite.Frame = _headFrame;
	}
	
	public void SetProne(bool prone)
	{
		_isProne = prone;
		UpdateProneRotation();
	}
	
	private void UpdateProneRotation()
	{
		foreach (var part in _bodyParts)
		{
			var sprite = GetNodeOrNull<Sprite2D>(part);
			if (sprite != null && sprite.Visible)
			{
				if (_isProne)
				{
					sprite.Rotation = Mathf.Pi / 2;
				}
				else
				{
					sprite.Rotation = 0;
				}
			}
		}
		
		foreach (var part in _gearParts)
		{
			var sprite = GetNodeOrNull<Sprite2D>(part);
			if (sprite != null && sprite.Visible)
			{
				if (_isProne)
				{
					sprite.Rotation = Mathf.Pi / 2;
				}
				else
				{
					sprite.Rotation = 0;
				}
			}
		}
	}
	
	public void PlayDoAfterAnimation(float duration)
	{
		_doAfterTween?.Kill();
		_doAfterTween = CreateTween();
		
		var doAfterIndicator = new Sprite2D();
		doAfterIndicator.Texture = ResourceLoader.Load<Texture2D>("uid://cqglc2mfqbup1");
		doAfterIndicator.Hframes = 20;
		doAfterIndicator.Vframes = 1;
		doAfterIndicator.Frame = 0;
		doAfterIndicator.Position = new Vector2(0, -40);
		doAfterIndicator.ZIndex = 1000;
		AddChild(doAfterIndicator);
		
		_doAfterTween.TweenProperty(doAfterIndicator, "frame", 19, duration);
		_doAfterTween.TweenCallback(Callable.From(() => doAfterIndicator.QueueFree()));
	}

	public void PlayHitEffect(Vector2 globalPosition)
	{
		var hitEffect = new Sprite2D();
		hitEffect.Texture = ResourceLoader.Load<Texture2D>("uid://dod1d5aflblc2");
		hitEffect.Hframes = 6;
		hitEffect.Vframes = 1;
		hitEffect.Frame = 0;
		hitEffect.Position = ToLocal(globalPosition);
		hitEffect.ZIndex = 100;
		AddChild(hitEffect);
		
		var hitTween = CreateTween();
		hitTween.TweenProperty(hitEffect, "frame", 5, 0.15);
		hitTween.TweenCallback(Callable.From(() => hitEffect.QueueFree()));
	}

	public void PlayThrustAndHitEffect(Vector2 thrustDirection, Vector2 hitGlobalPosition)
	{
		PlayThrustTween(thrustDirection);
		PlayHitEffect(hitGlobalPosition);
	}

	private void UpdateZLevels(int headDir)
	{
		var headSprite = GetNodeOrNull<Sprite2D>("Head");
		var hairSprite = GetNodeOrNull<Sprite2D>("Hair");
		var eyesSprite = GetNodeOrNull<Sprite2D>("Eyes");
		var facialHairSprite = GetNodeOrNull<Sprite2D>("Facial_Hair");
		var bodySprite = GetNodeOrNull<Sprite2D>("Body");
		
		if (headSprite == null || hairSprite == null || bodySprite == null) return;
		
		if (headDir == 0)
		{
			headSprite.ZIndex = bodySprite.ZIndex;
			if (eyesSprite != null) eyesSprite.ZIndex = bodySprite.ZIndex;
			hairSprite.ZIndex = bodySprite.ZIndex + 1;
			if (facialHairSprite != null && facialHairSprite.Visible) facialHairSprite.ZIndex = bodySprite.ZIndex + 1;
		}
		else
		{
			hairSprite.ZIndex = bodySprite.ZIndex + 1;
			headSprite.ZIndex = bodySprite.ZIndex + 1;
			if (eyesSprite != null) eyesSprite.ZIndex = bodySprite.ZIndex + 1;
			if (facialHairSprite != null && facialHairSprite.Visible) facialHairSprite.ZIndex = bodySprite.ZIndex + 1;
		}
	}
	
	
}
