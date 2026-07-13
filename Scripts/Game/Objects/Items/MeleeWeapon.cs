using Godot;

namespace GodotStation.Game.Objects.Items;

// A melee weapon - just carries a damage value heavier than bare fists.
// Actual attack resolution (range/adjacency, intent handling) lives in
// PlayerMob.DoAttack since it's the same code path whether you're armed
// or not; this only answers "how hard does this thing hit."
public partial class MeleeWeapon : Item
{
    [Export] public float Damage = 12f;
}
