using Godot;

[GlobalClass]
public partial class FoodItem : Item
{
	[Export] public float HealingAmount = 10.0f;
	[Export] public float PainReduction = 1.0f;
	[Export] public float QualityMultiplier = 1.0f;
	[Export] public float SpoilTime = 300.0f; // 5 minutes
	
	// Runtime properties (not exported).
	private float _spoilTimer = 0f;
	private bool _isSpoiled = false;
	
	public void Initialize()
	{
		_spoilTimer = SpoilTime;
		_isSpoiled = false;
	}
	
	public void UpdateSpoilage(float delta)
	{
		if (!_isSpoiled)
		{
			_spoilTimer -= delta;
			if (_spoilTimer <= 0)
			{
				Spoil();
			}
		}
	}
	
	private void Spoil()
	{
		_isSpoiled = true;
		QualityMultiplier = 0.1f; // Spoiled food has very low quality
		HealingAmount *= 0.1f; // Spoiled food heals less
		PainReduction = 0f; // Spoiled food doesn't reduce pain
	}
	
	public bool IsSpoiled() => _isSpoiled;
	public float GetSpoilProgress() => Mathf.Clamp(1.0f - (_spoilTimer / SpoilTime), 0f, 1f);
}
