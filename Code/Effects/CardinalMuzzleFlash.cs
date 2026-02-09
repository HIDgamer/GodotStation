using Godot;

public partial class CardinalMuzzleFlash : Node2D
{
	[Export] public Texture2D MuzzleFlashTexture;
	[Export] public float AnimationDuration = 0.06f;
	
	private Sprite2D _flashSprite;
	private float _elapsed;
	
	public void Init(Vector2 direction)
	{
		if (MuzzleFlashTexture == null)
		{
			MuzzleFlashTexture = GD.Load<Texture2D>("res://Assets/Effects/FX/MuzzleFlash.png");
		}
		
		_flashSprite = new Sprite2D
		{
			Name = "MuzzleFlash",
			Texture = MuzzleFlashTexture,
			Hframes = 2,
			Vframes = 1,
			Frame = 0,
			ZIndex = 50
		};
		
		AddChild(_flashSprite);
		
		// Rotate to 4 cardinal directions only
		float rotation = GetCardinalRotation(direction);
		Rotation = rotation;
		
		_elapsed = 0f;
		
		// Start animation
		var tween = CreateTween();
		tween.TweenProperty(_flashSprite, "frame", 1, AnimationDuration);
		tween.TweenCallback(Callable.From(() => QueueFree()));
	}
	
	private static float GetCardinalRotation(Vector2 direction)
	{
		if (direction.Length() < 0.01f) return 0f;
		
		// Normalize direction
		direction = direction.Normalized();
		
		// Determine cardinal direction (0°, 90°, 180°, -90°)
		float angle = direction.Angle();
		
		// Snap to 4 directions: 0° (up), 90° (right), 180° (down), -90° (left)
		if (angle >= -Mathf.Pi/4 && angle < Mathf.Pi/4) // Right (90°)
			return Mathf.Pi / 2f;
		else if (angle >= Mathf.Pi/4 && angle < 3*Mathf.Pi/4) // Down (180°)
			return Mathf.Pi;
		else if (angle >= 3*Mathf.Pi/4 || angle < -3*Mathf.Pi/4) // Left (-90°)
			return -Mathf.Pi / 2f;
		else // Up (0°)
			return 0f;
	}
}