using GodotStation.Core.Atoms;

namespace GodotStation.Game.World.Turfs;

// Dense, opaque structural turf. Reveals a FloorTurf when Integrity hits 0
// via ApplyDamage (see Turf.BaseTurf/Destroyed) - matches ucfss13's own
// wall-destruction-reveals-the-deck-beneath-it model. Deliberately doesn't
// spawn a girder/wreckage structure on the revealed floor yet - that needs
// a real construction system (turn girder + materials back into a wall) to
// be worth building, which doesn't exist yet either; add it alongside that
// system, not as untested plumbing now.
public class WallTurf : ClosedTurf
{
    public WallTurf()
    {
        AtomName = "Wall";
        Integrity = 300f;
        MaxIntegrity = 300f;
        SetIcon("res://Icons/turf/walls/walls.png", "metal");
        BaseTurf = () => new FloorTurf();
    }
}

// Reinforced variant - same reveal behavior, just a much larger HP pool.
public sealed class ReinforcedWallTurf : WallTurf
{
    public ReinforcedWallTurf()
    {
        AtomName = "Reinforced Wall";
        Integrity = 500f;
        MaxIntegrity = 500f;
        SetIcon("res://Icons/turf/walls/walls.png", "r_wall");
    }
}
