using Godot;

[GlobalClass]
public partial class MedicalItem : ConsumableItem
{
	[Export] public float PainReduction = 0.0f;
	[Export] public bool CanUseOnOthers = true;

	public MedicalItem()
	{
		ItemCategory = Category.Consumable;
	}

	public void ApplyTo(Mob target)
	{
		if (target == null) return;
		Consume(target);
		if (PainReduction <= 0f) return;
		target.GetNodeOrNull<HealthSystem>("HealthSystem")?.ApplyPainReduction(PainReduction);
	}
}
