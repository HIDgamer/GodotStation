using Godot;

[GlobalClass]
public partial class MeleeWeapon : WeaponItem
{
	[Export] public float Reach = 48.0f;
	[Export] public float StunChance = 0.1f;
	[Export] public float KnockdownChance = 0.05f;
	[Export] public float DisarmChance = 0.2f;
	[Export] public bool CanDisarm = true;
	[Export] public bool CanStun = true;
	[Export] public bool CanKnockdown = false;
	
public void Initialize()
	{
		IsRanged = false;
		DamageType = DamageType.Brute;
	}
	
	public bool CanDisarmTarget()
	{
		return CanDisarm && DamageAmount > 5;
	}
	
	public bool CanStunTarget()
	{
		return CanStun && DamageAmount > 10;
	}
	
	public bool CanKnockdownTarget()
	{
		return CanKnockdown && DamageAmount > 15;
	}
}
