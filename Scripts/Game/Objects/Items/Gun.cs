using Godot;
using GodotStation.Core.World;
using GodotStation.Game.Mobs;

namespace GodotStation.Game.Objects.Items;

// A ranged weapon. Variance between guns (pistol vs rifle) is still data
// (Damage/RangeCells exported per scene instance) - this subclass exists
// only because "fire in a direction" is genuinely different behavior from
// a bare Item, not because every gun needs its own script.
public partial class Gun : Item
{
    [Export] public float Damage = 20f;
    [Export] public int RangeCells = 8;

    // Walks cell-by-cell from the shooter's position, stopping at the first
    // dense turf or the first mob hit. No falloff/spread/penetration - a
    // straight hitscan lane, matching the facing-direction combat model
    // rather than mouse-aimed targeting (not built yet).
    public bool Fire(Vector2I fromCell, Vector2I direction, out Mob? hitMob)
    {
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        hitMob = null;

        for (var i = 1; i <= RangeCells; i++)
        {
            var cell = fromCell + direction * i;
            if (worldGrid.IsDense(cell)) return false;

            foreach (var occupant in worldGrid.GetOccupants(cell))
            {
                if (occupant is Mob mob)
                {
                    hitMob = mob;
                    return true;
                }
            }
        }

        return false;
    }
}
