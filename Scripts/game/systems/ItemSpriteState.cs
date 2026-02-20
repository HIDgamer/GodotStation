using Godot;

[GlobalClass]
public partial class ItemSpriteState : Resource
{
	[Export] public string StateId = "default";
	[Export] public Texture2D IconTexture;
	[Export] public Texture2D InHandLeftTexture;
	[Export] public Texture2D InHandRightTexture;
	[Export] public Texture2D WornTexture;
	[Export] public int IconHframes = 0;
	[Export] public int IconVframes = 0;
	[Export] public int InHandHframes = 0;
	[Export] public int InHandVframes = 0;
	
	// Frame selection properties - specify which frame to use from sprite sheets.
	[Export] public int IconFrame = 0;
	[Export] public int InHandLeftFrame = 0;
	[Export] public int InHandRightFrame = 0;
	[Export] public int WornFrame = 0;
}
