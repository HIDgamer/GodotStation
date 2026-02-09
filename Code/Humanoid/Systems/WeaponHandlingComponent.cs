using Godot;

/// Stub component for weapon handling - ranged weapons removed
public partial class WeaponHandlingComponent : Node, IMobSystem
{
	private Mob _owner;
	private Inventory _inventory;
	
	public void Init(Mob mob)
	{
		_owner = mob;
		_inventory = mob.GetNodeOrNull<Inventory>("Inventory");
	}
	
	public void Process(double delta) { }
	public void Cleanup() { }
	
	// Ranged weapon methods removed - stub methods for compatibility
	public bool TryFireAt(Vector2 targetPos) => false;
	public bool TryClickReloadOrUnload(Vector2 clickPos) => false;
	public void ToggleReady() { }
	public void ToggleSafety() { }
	public void Cock() { }
	public void Reload() { }
	public void QuickUnloadDrop() { }
}
