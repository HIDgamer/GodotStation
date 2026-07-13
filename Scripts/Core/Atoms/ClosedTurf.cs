namespace GodotStation.Core.Atoms;

// Solid turf base (ucfss13's /turf/closed convention, studied as design
// reference only) - dense and opaque by default. Concrete subtypes (walls,
// reinforced walls...) live under Scripts/Game/World/Turfs.
public abstract class ClosedTurf : Turf
{
    protected ClosedTurf()
    {
        IsDense = true;
        BlocksLight = true;
    }
}
