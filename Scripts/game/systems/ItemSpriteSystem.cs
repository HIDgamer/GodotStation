using Godot;
using System.Collections.Generic;
using System.Linq;

public partial class ItemSpriteSystem : Node2D
{
	[Export] public Texture2D IconTexture;
	[Export] public Texture2D InHandLeftTexture;
	[Export] public Texture2D InHandRightTexture;
	[Export] public Texture2D WornTexture;
	[Export] public int InHandHframes = 4;
	[Export] public int InHandVframes = 1;
	[Export] public int IconHframes = 1;
	[Export] public int IconVframes = 1;
	
	[Export] public string DefaultStateId = "default";
	[Export] public Godot.Collections.Array<ItemSpriteState> States = new();
	[Export] public Godot.Collections.Array<ItemSpriteOverlay> Overlays = new();
	
	private Sprite2D _iconSprite;
	private Sprite2D _inHandLeftSprite;
	private Sprite2D _inHandRightSprite;
	private Sprite2D _wornSprite;
	
	private readonly Dictionary<string, ItemSpriteState> _stateLookup = new();
	private readonly Dictionary<string, OverlaySprites> _overlaySprites = new();
	private string _currentStateId;
	private bool _showingIcon;
	private bool _showingWorn;
	private bool _showingLeftHand;
	
	public override void _Ready()
	{
		CacheStatesAndOverlays();
		_iconSprite = new Sprite2D { Name = "Icon", Texture = IconTexture, Visible = true };
		_iconSprite.Hframes = Mathf.Max(1, IconHframes);
		_iconSprite.Vframes = Mathf.Max(1, IconVframes);
		_inHandLeftSprite = new Sprite2D { 
			Name = "InHandLeft", 
			Texture = InHandLeftTexture,
			Hframes = InHandHframes,
			Vframes = InHandVframes,
			Visible = false
		};
		_inHandRightSprite = new Sprite2D { 
			Name = "InHandRight", 
			Texture = InHandRightTexture,
			Hframes = InHandHframes,
			Vframes = InHandVframes,
			Visible = false
		};
		_wornSprite = new Sprite2D {
			Name = "Worn",
			Texture = WornTexture,
			Visible = false
		};
		
		AddChild(_iconSprite);
		AddChild(_inHandLeftSprite);
		AddChild(_inHandRightSprite);
		AddChild(_wornSprite);
		
		BuildOverlaySprites();
		SetState(DefaultStateId);
	}
	
	public void ShowIcon()
	{
		if (_iconSprite == null) return;
		_showingIcon = true;
		_showingWorn = false;
		_showingLeftHand = false;
		_iconSprite.Visible = true;
		_inHandLeftSprite.Visible = false;
		_inHandRightSprite.Visible = false;
		_wornSprite.Visible = false;
		UpdateOverlayVisibility();
	}
	
	public void ShowInHand(int direction, bool isLeftHand)
	{
		if (_iconSprite == null) return;
		_showingIcon = false;
		_showingWorn = false;
		_showingLeftHand = isLeftHand;
		_iconSprite.Visible = false;
		_wornSprite.Visible = false;
		
		if (isLeftHand)
		{
			_inHandLeftSprite.Visible = true;
			_inHandLeftSprite.Frame = direction;
			_inHandRightSprite.Visible = false;
		}
		else
		{
			_inHandRightSprite.Visible = true;
			_inHandRightSprite.Frame = direction;
			_inHandLeftSprite.Visible = false;
		}
		UpdateOverlayVisibility();
	}
	
	public void ShowWorn()
	{
		if (_wornSprite == null) return;
		_showingIcon = false;
		_showingWorn = true;
		_showingLeftHand = false;
		_iconSprite.Visible = false;
		_inHandLeftSprite.Visible = false;
		_inHandRightSprite.Visible = false;
		_wornSprite.Visible = true;
		UpdateOverlayVisibility();
	}
	
	public Sprite2D GetIconSprite() => _iconSprite;
	public Texture2D GetIconTexture() => IconTexture;
	
	public Texture2D GetIconTextureAtFrame(int frame = -1)
	{
		if (IconTexture == null) return null;
		
		int targetFrame = frame >= 0 ? frame : (_iconSprite?.Frame ?? 0);
		int totalFrames = Mathf.Max(1, IconHframes * IconVframes);
		
		if (totalFrames <= 1)
		{
			// No frames, return full texture.
			return IconTexture;
		}
		
		// Create an atlastexture to extract a single frame.
		var atlas = new AtlasTexture();
		atlas.Atlas = IconTexture;
		
		// Calculate frame position in the spritesheet.
		int hframes = Mathf.Max(1, IconHframes);
		int vframes = Mathf.Max(1, IconVframes);
		targetFrame = Mathf.Clamp(targetFrame, 0, totalFrames - 1);
		
		// Get the texture size.
		var textureSize = IconTexture.GetSize();
		float frameWidth = textureSize.X / hframes;
		float frameHeight = textureSize.Y / vframes;
		
		// Calculate which frame row/col.
		int col = targetFrame % hframes;
		int row = targetFrame / hframes;
		
		// Set the region for this frame.
		atlas.Region = new Rect2(col * frameWidth, row * frameHeight, frameWidth, frameHeight);
		
		return atlas;
	}
	
	public void SetIconFrame(int frame)
	{
		if (_iconSprite == null) return;
		int total = Mathf.Max(1, _iconSprite.Hframes * _iconSprite.Vframes);
		_iconSprite.Frame = Mathf.Clamp(frame, 0, total - 1);
	}
	
	public void SetState(string stateId)
	{
		_currentStateId = stateId;
		if (!_stateLookup.TryGetValue(stateId, out var state))
			state = null;
		
		ApplyStateTextures(state);
	}
	
	public void SetOverlay(string overlayId, bool enabled)
	{
		if (!_overlaySprites.TryGetValue(overlayId, out var sprites)) return;
		sprites.Enabled = enabled;
		
		// Apply frame settings when overlay is toggled.
		if (enabled)
		{
			var overlay = Overlays.FirstOrDefault(o => o != null && o.OverlayId == overlayId);
			if (overlay != null)
				ApplyOverlayFrameSettings(sprites, overlay);
		}
		
		UpdateOverlayVisibility();
	}
	
	private void CacheStatesAndOverlays()
	{
		_stateLookup.Clear();
		foreach (var state in States)
		{
			if (state == null || string.IsNullOrEmpty(state.StateId)) continue;
			_stateLookup[state.StateId] = state;
		}
	}
	
	private void ApplyStateTextures(ItemSpriteState state)
	{
		var iconTexture = state?.IconTexture ?? IconTexture;
		var leftTexture = state?.InHandLeftTexture ?? InHandLeftTexture;
		var rightTexture = state?.InHandRightTexture ?? InHandRightTexture;
		var wornTexture = state?.WornTexture ?? WornTexture;
		
		_iconSprite.Texture = iconTexture;
		_inHandLeftSprite.Texture = leftTexture;
		_inHandRightSprite.Texture = rightTexture;
		_wornSprite.Texture = wornTexture;
		
		int iconHframes = state?.IconHframes > 0 ? state.IconHframes : IconHframes;
		int iconVframes = state?.IconVframes > 0 ? state.IconVframes : IconVframes;
		_iconSprite.Hframes = Mathf.Max(1, iconHframes);
		_iconSprite.Vframes = Mathf.Max(1, iconVframes);
		
		int hframes = state?.InHandHframes > 0 ? state.InHandHframes : InHandHframes;
		int vframes = state?.InHandVframes > 0 ? state.InHandVframes : InHandVframes;
		
		_inHandLeftSprite.Hframes = hframes;
		_inHandRightSprite.Hframes = hframes;
		_inHandLeftSprite.Vframes = vframes;
		_inHandRightSprite.Vframes = vframes;
		
		// Apply frame settings from state.
		ApplyFrameSettings(_iconSprite, state?.IconFrame ?? 0);
		ApplyFrameSettings(_inHandLeftSprite, state?.InHandLeftFrame ?? 0);
		ApplyFrameSettings(_inHandRightSprite, state?.InHandRightFrame ?? 0);
		ApplyFrameSettings(_wornSprite, state?.WornFrame ?? 0);
	}
	
	private void BuildOverlaySprites()
	{
		_overlaySprites.Clear();
		foreach (var overlay in Overlays)
		{
			if (overlay == null || string.IsNullOrEmpty(overlay.OverlayId)) continue;
			
			var sprites = new OverlaySprites
			{
				OverlayId = overlay.OverlayId,
				Icon = CreateOverlaySprite($"OverlayIcon_{overlay.OverlayId}", overlay.IconTexture, overlay.ZIndex, overlay.Offset),
				InHandLeft = CreateOverlaySprite($"OverlayLeft_{overlay.OverlayId}", overlay.InHandLeftTexture, overlay.ZIndex, overlay.Offset),
				InHandRight = CreateOverlaySprite($"OverlayRight_{overlay.OverlayId}", overlay.InHandRightTexture, overlay.ZIndex, overlay.Offset),
				Worn = CreateOverlaySprite($"OverlayWorn_{overlay.OverlayId}", overlay.WornTexture, overlay.ZIndex, overlay.Offset),
				Enabled = overlay.EnabledByDefault
			};
			
			_overlaySprites[overlay.OverlayId] = sprites;
		}
		
		UpdateOverlayVisibility();
	}
	
	private Sprite2D CreateOverlaySprite(string name, Texture2D texture, int zIndex, Vector2 offset)
	{
		var sprite = new Sprite2D
		{
			Name = name,
			Texture = texture,
			Visible = false,
			ZIndex = zIndex,
			Position = offset
		};
		AddChild(sprite);
		return sprite;
	}
	
	private void ApplyOverlayFrameSettings(OverlaySprites sprites, ItemSpriteOverlay overlay)
	{
		if (sprites == null || overlay == null) return;
		
		ApplyFrameSettings(sprites.Icon, overlay.IconFrame);
		ApplyFrameSettings(sprites.InHandLeft, overlay.InHandLeftFrame);
		ApplyFrameSettings(sprites.InHandRight, overlay.InHandRightFrame);
		ApplyFrameSettings(sprites.Worn, overlay.WornFrame);
	}
	
	private void UpdateOverlayVisibility()
	{
		foreach (var pair in _overlaySprites)
		{
			var sprites = pair.Value;
			bool enabled = sprites.Enabled;
			
			sprites.Icon.Visible = enabled && _showingIcon;
			sprites.Worn.Visible = enabled && _showingWorn;
			sprites.InHandLeft.Visible = enabled && !_showingIcon && !_showingWorn && _showingLeftHand;
			sprites.InHandRight.Visible = enabled && !_showingIcon && !_showingWorn && !_showingLeftHand;
		}
	}
	
	private void ApplyFrameSettings(Sprite2D sprite, int frame)
	{
		if (sprite == null) return;
		
		// Apply frame setting if valid.
		if (frame >= 0)
		{
			int totalFrames = sprite.Hframes * sprite.Vframes;
			if (totalFrames > 1)
			{
				sprite.Frame = Mathf.Clamp(frame, 0, totalFrames - 1);
			}
		}
	}
	
	
	public void SyncInHandFrame(int frame)
	{
		if (_inHandLeftSprite != null)
			_inHandLeftSprite.Frame = Mathf.Clamp(frame, 0, _inHandLeftSprite.Hframes * _inHandLeftSprite.Vframes - 1);
		if (_inHandRightSprite != null)
			_inHandRightSprite.Frame = Mathf.Clamp(frame, 0, _inHandRightSprite.Hframes * _inHandRightSprite.Vframes - 1);
	}
	
	private sealed class OverlaySprites
	{
		public string OverlayId;
		public Sprite2D Icon;
		public Sprite2D InHandLeft;
		public Sprite2D InHandRight;
		public Sprite2D Worn;
		public bool Enabled;
	}
}
