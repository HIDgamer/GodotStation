using Godot;

namespace GodotStation.Core.Atoms;

// Anything that can occupy and move between grid cells. The actual movement
// backend (grid-snap vs. continuous pixel) lives in a MovementController
// component (see Scripts/Core/World) - this base just holds the atom's
// authoritative grid-space position, which every other system (adjacency,
// interaction range, line-of-sight) reasons about regardless of which
// backend is producing it.
public abstract partial class MovableAtom : Atom
{
    [Signal] public delegate void GridCellChangedEventHandler(Vector2I oldCell, Vector2I newCell);

    public Vector2I GridCell { get; private set; }

    // Internal - only WorldGrid.MoveOccupant should call this, so occupancy
    // lists and this property can never drift out of sync. Everything else
    // that wants to move something goes through MovementController, which
    // goes through WorldGrid.
    internal void SetGridCell(Vector2I newCell)
    {
        if (newCell == GridCell) return;
        var old = GridCell;
        GridCell = newCell;
        EmitSignal(SignalName.GridCellChanged, old, newCell);
    }
}
