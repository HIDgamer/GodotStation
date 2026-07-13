namespace GodotStation.Core.Atoms;

// Walkable turf base (ucfss13's /turf/open convention, studied as design
// reference only) - not dense, doesn't block light by default. Concrete
// subtypes (floor, plating, space...) live under Scripts/Game/World/Turfs.
public abstract class OpenTurf : Turf
{
    protected OpenTurf()
    {
        IsDense = false;
        BlocksLight = false;
    }
}
