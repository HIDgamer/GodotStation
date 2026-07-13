using GodotStation.Core.Atoms;

namespace GodotStation.Game.World.Turfs;

// Dense, opaque structural turf. Becomes non-dense once destroyed (Integrity
// hits 0 via ApplyDamage) rather than being removed outright - a destroyed
// wall is still a distinct game state (rubble/wreckage), not empty space.
public sealed class WallTurf : ClosedTurf
{
    public WallTurf()
    {
        AtomName = "Wall";
        Integrity = 300f;
        MaxIntegrity = 300f;
        SetIcon("res://Icons/turf/walls/walls.png", "r_wall");
    }

    protected override void OnDestroyed()
    {
        IsDense = false;
        BlocksLight = false;
    }
}
