namespace GodotStation.Core.Atoms;

// A named region grouping turf cells (a room, a ship deck section...).
// Not a Node for the same reason as Turf - named GameArea (not just "Area")
// to avoid confusion with Godot's own Area2D. Holds room-level state (power
// availability, atmosphere-adjacent flags later) that turfs/movables query,
// not a visual scene presence of its own.
public class GameArea : IAtom
{
    public string AtomName { get; set; } = "";
    public string Description { get; set; } = "";
    public float Integrity { get; set; } = 100f;
    public float MaxIntegrity { get; set; } = 100f;

    public bool HasPower { get; set; } = true;

    public virtual string Examine()
        => string.IsNullOrEmpty(Description) ? AtomName : $"{AtomName}\n{Description}";
}
