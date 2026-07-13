using GodotStation.Core.Atoms;

namespace GodotStation.Game.Objects;

// Base for placed, non-mob world objects - items, structures, effects.
// Concrete variance (a rifle vs. a pistol) is expressed as data (a stat
// Resource) driving a shared behavior script, not as ever-deeper subclasses -
// reserve actual subclassing here for genuinely different behavior
// (Objects.Items.Gun vs Objects.Structures.Locker), not stat differences.
public abstract partial class WorldObject : MovableAtom
{
}
