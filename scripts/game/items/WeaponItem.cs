using Godot;

[GlobalClass]
public partial class WeaponItem : Item
{
	[Export] public float DamageAmount = 10.0f;
	[Export] public DamageType DamageType = DamageType.Brute;
	[Export] public float AttackRange = 32.0f;
	[Export] public float AttackCooldown = 1.0f;
	[Export] public float Accuracy = 0.8f;
	[Export] public string AttackAnimation = "melee";
	[Export] public bool IsTwoHanded = false;
	
	// Ranged weapon properties.
	[Export] public bool IsRanged = false;
	[Export] public int MagazineCapacity = 0;
	[Export] public int CurrentAmmo = 0;
	[Export] public float FireRate = 0.5f;
	[Export] public float ProjectileSpeed = 500.0f;
	[Export] public float Recoil = 0.1f;
	[Export] public string ProjectileScene = "";
	
	// Tool properties.
	[Export] public virtual bool IsTool { get; set; } = false;
	[Export] public virtual string ToolType { get; set; } = "";
	[Export] public virtual float ToolEfficiency { get; set; } = 1.0f;
	[Export] public virtual string ToolAnimation { get; set; } = "use";
	
	// Medical properties.
	[Export] public virtual bool IsMedical { get; set; } = false;
	[Export] public virtual float HealingAmount { get; set; } = 0.0f;
	[Export] public virtual float PainReduction { get; set; } = 0.0f;
	[Export] public virtual float StabilizeChance { get; set; } = 0.5f;
	[Export] public virtual string MedicalAnimation { get; set; } = "inject";
	
	// Construction properties.
	[Export] public virtual bool IsConstruction { get; set; } = false;
	[Export] public virtual float BuildSpeed { get; set; } = 1.0f;
	[Export] public virtual string ConstructionType { get; set; } = "";
	[Export] public virtual string ConstructionAnimation { get; set; } = "build";
	
	// Electronics properties.
	[Export] public virtual bool IsElectronic { get; set; } = false;
	[Export] public virtual float BatteryCapacity { get; set; } = 100.0f;
	[Export] public virtual float CurrentCharge { get; set; } = 100.0f;
	[Export] public virtual string ElectronicFunction { get; set; } = "";
	[Export] public virtual string ElectronicAnimation { get; set; } = "activate";
	
	// Clothing properties.
	[Export] public bool IsClothing = false;
	[Export] public float ProtectionValue = 0.0f;
	[Export] public float Coverage = 1.0f;
	[Export] public string ClothingSlot = "uniform";
	[Export] public string ClothingAnimation = "equip";
	
	// Consumable properties.
	[Export] public bool IsConsumable = false;
	[Export] public float ConsumptionTime = 1.0f;
	[Export] public string ConsumableEffect = "";
	[Export] public string ConsumableAnimation = "consume";
	
	// Special properties.
	[Export] public bool IsThrowable = false;
	[Export] public float ThrowForce = 200.0f;
	[Export] public float ThrowRange = 100.0f;
	[Export] public string ThrowableEffect = "";
	
	// Item interactions.
	public enum InteractionType { None, MeleeAttack, RangedAttack, UseTool, MedicalTreatment, Consume, Equip, Activate }
	
	public InteractionType GetInteractionType()
	{
		if (IsRanged && CurrentAmmo > 0) return InteractionType.RangedAttack;
		if (DamageAmount > 0) return InteractionType.MeleeAttack;
		if (IsTool) return InteractionType.UseTool;
		if (IsMedical) return InteractionType.MedicalTreatment;
		if (IsConsumable) return InteractionType.Consume;
		if (IsClothing) return InteractionType.Equip;
		if (IsElectronic) return InteractionType.Activate;
		return InteractionType.None;
	}
	
	public bool CanUse()
	{
		if (IsRanged && CurrentAmmo <= 0) return false;
		if (IsElectronic && CurrentCharge <= 0) return false;
		return true;
	}
	
	public void UseAmmo(int amount = 1)
	{
		if (IsRanged)
		{
			CurrentAmmo = Mathf.Max(0, CurrentAmmo - amount);
		}
	}
	
	public void UseCharge(float amount = 10.0f)
	{
		if (IsElectronic)
		{
			CurrentCharge = Mathf.Max(0, CurrentCharge - amount);
		}
	}
	
	public void Reload(int ammoCount)
	{
		if (IsRanged)
		{
			CurrentAmmo = Mathf.Min(MagazineCapacity, CurrentAmmo + ammoCount);
		}
	}
	
	public void Recharge(float chargeAmount)
	{
		if (IsElectronic)
		{
			CurrentCharge = Mathf.Min(BatteryCapacity, CurrentCharge + chargeAmount);
		}
	}
}
