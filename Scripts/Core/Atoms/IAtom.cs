namespace GodotStation.Core.Atoms;

// Shared contract for anything "atom-like" - world objects/mobs (real scene
// nodes) and turf/area (lightweight non-Node data, since a map can have tens
// of thousands of turf cells and each one being a full Node would be
// wasteful). A plain interface rather than a shared non-Node base class,
// since C# single inheritance means the Node2D-based MovableAtom chain can't
// also share a non-Node base - see Atom's header comment for the full reasoning.
public interface IAtom
{
    string AtomName { get; set; }
    string Description { get; set; }
    float Integrity { get; set; }
    float MaxIntegrity { get; set; }

    string Examine();
}
