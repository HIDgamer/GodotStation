using Godot;

[GlobalClass]
public partial class ItemSpriteOverlay : Resource
{
	[Export] public string OverlayId = "default";
	[Export] public Texture2D IconTexture;
	[Export] public Texture2D InHandLeftTexture;
	[Export] public Texture2D InHandRightTexture;
	[Export] public Texture2D WornTexture;
	[Export] public bool EnabledByDefault = false;
	[Export] public int ZIndex = 1;
	[Export] public Vector2 Offset = Vector2.Zero;
	
	// Frame selection properties - specify which frame to use from sprite sheets.
	[Export] public int IconFrame = 0;
	[Export] public int InHandLeftFrame = 0;
	[Export] public int InHandRightFrame = 0;
	[Export] public int WornFrame = 0;
}
