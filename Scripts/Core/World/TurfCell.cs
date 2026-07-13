using System.Collections.Generic;
using GodotStation.Core.Atoms;

namespace GodotStation.Core.World;

// One grid cell's full state - which turf occupies it, which area it
// belongs to, and which movables are currently standing in it. This is the
// canonical/authoritative world-state unit regardless of movement mode -
// see WorldGrid's header comment.
public sealed class TurfCell
{
    public Turf? Turf;
    public GameArea? Area;
    public readonly List<MovableAtom> Occupants = new();
}
