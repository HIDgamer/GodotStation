using GodotStation.Core.Atoms;

namespace GodotStation.Game.World.Turfs;

// Plain walkable deck plating. The default turf for enclosed, pressurized
// areas - most of a map is this.
public sealed class FloorTurf : OpenTurf
{
    public FloorTurf()
    {
        AtomName = "Floor";
        SetIcon("res://Icons/turf/floors/floors.png", "floor");
    }
}
