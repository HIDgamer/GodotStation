using Godot;

[GlobalClass]
public partial class RangedWeapon : WeaponItem
{
	[Export] public int BurstCount = 1;
	[Export] public float BurstDelay = 0.1f;
	[Export] public float Spread = 0.05f;
	[Export] public float Penetration = 0.0f;
	[Export] public float ArmorPiercing = 0.0f;
	[Export] public bool HasSilencer = false;
	[Export] public bool HasLaser = false;
	[Export] public bool HasFlashlight = false;
	[Export] public string AmmoType = "bullet";
	[Export] public float ReloadTime = 1.5f;
	[Export] public bool IsAutomatic = false;
	[Export] public bool IsBurstFire = false;
	
	public void Initialize()
	{
		IsRanged = true;
	}
	
	public bool CanFire()
	{
		return CurrentAmmo > 0 && CanUse();
	}
	
	public void FireProjectile(Vector2 direction, Vector2 position, Node parentScene)
	{
		if (!CanFire()) return;
		
		// Create projectile.
		if (!string.IsNullOrEmpty(ProjectileScene))
		{
			var projectileScene = GD.Load<PackedScene>(ProjectileScene);
			if (projectileScene != null)
			{
				var projectile = projectileScene.Instantiate<Node2D>();
				projectile.Position = position;
				
				// Add spread.
				var spreadAngle = (GD.Randf() - 0.5f) * Spread;
				var finalDirection = direction.Rotated(spreadAngle);
				
				// Set projectile properties.
				if (projectile.HasMethod("SetVelocity"))
				{
					projectile.Call("SetVelocity", finalDirection * ProjectileSpeed);
				}
				if (projectile.HasMethod("SetDamage"))
				{
					projectile.Call("SetDamage", DamageAmount);
				}
				if (projectile.HasMethod("SetPenetration"))
				{
					projectile.Call("SetPenetration", Penetration);
				}
				
				// Add to scene.
				if (parentScene != null)
				{
					parentScene.AddChild(projectile);
				}
			}
		}
		
		UseAmmo();
	}
	
	public void ReloadWeapon()
	{
		if (MagazineCapacity > 0)
		{
			CurrentAmmo = MagazineCapacity;
		}
	}
}
