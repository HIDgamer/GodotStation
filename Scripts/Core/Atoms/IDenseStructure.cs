namespace GodotStation.Core.Atoms;

// Minimal contract for a non-turf object that occupies a cell and
// contributes density (Door today; windows/tables/etc. later) - lets
// WorldGrid/TurfCell (Core) check density without depending on any concrete
// Game-layer structure type. Deliberately just IsDense - extend only when
// something else (BlocksLight, ...) actually needs a consumer.
public interface IDenseStructure
{
    bool IsDense { get; }
}
