using Godot;

[GlobalClass]
public partial class Item : Resource
{
	[Export] public string ItemName = "Item";
	[Export] public string Description = "";
	[Export] public Texture2D Icon;
	[Export] public string ScenePath = ""; // Path to world item scene. Must use UID format (uid://...) for export compatibility
	[Export] public float Weight = 1.0f;
	[Export] public int MaxStack = 1;
	[Export] public bool IsRuntimeUnique = false;
	
	// Frame settings for custom sprite display.
	[Export] public int IconFrame = 0;
	[Export] public int InHandLeftFrame = 0;
	[Export] public int InHandRightFrame = 0;
	[Export] public int WornFrame = 0;
	
	// Icon sprite sheet configuration.
	[Export] public int IconHframes = 1;
	[Export] public int IconVframes = 1;
	
	public enum Category { Tool, Weapon, Consumable, Clothing, Misc }
	[Export] public Category ItemCategory = Category.Misc;
	
	public Texture2D GetIconWithFrame()
	{
		if (Icon == null) return null;
		
		int totalFrames = Mathf.Max(1, IconHframes * IconVframes);
		
		// Single frame - no need for atlastexture.
		if (totalFrames <= 1)
		{
			return Icon;
		}
		
		// Multi-frame - create atlastexture for current frame.
		var atlas = new AtlasTexture();
		atlas.Atlas = Icon;
		
		int hframes = Mathf.Max(1, IconHframes);
		int vframes = Mathf.Max(1, IconVframes);
		int frame = Mathf.Clamp(IconFrame, 0, totalFrames - 1);
		
		// Get texture size.
		var textureSize = Icon.GetSize();
		float frameWidth = textureSize.X / hframes;
		float frameHeight = textureSize.Y / vframes;
		
		// Calculate row and column.
		int col = frame % hframes;
		int row = frame / hframes;
		
		// Set region for this frame.
		atlas.Region = new Rect2(col * frameWidth, row * frameHeight, frameWidth, frameHeight);
		
		return atlas;
	}
}
