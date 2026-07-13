using System;
using System.Collections.Generic;
using Godot;
using GodotStation.Core.Atoms;

namespace GodotStation.Core.World;

// The canonical, always-grid-based world state, regardless of which
// movement mode (grid-snap or pixel) is active. Every position-dependent
// system (adjacency, interaction range, line-of-sight, pathfinding) reasons
// about the world through this API, never through MovementController's
// backend-specific state directly - that's what lets the grid/pixel toggle
// exist without forking every system that cares "where is entity X".
public partial class WorldGrid : Node
{
    // Shared default for code that needs to convert cell<->world space outside
    // of a MovementController instance (map bootstrap, spawn placement). Each
    // MovementController's own GridCellSize export defaults to the same value
    // but can diverge per-entity if ever needed - this constant is just the
    // map-authoring default, not an enforced global.
    public const float DefaultCellSize = 32f;

    private readonly Dictionary<Vector2I, TurfCell> _cells = new();
    private readonly Dictionary<Vector2I, Action> _turfIconHandlers = new();
    private TurfTileMap? _turfTileMap;

    public override void _Ready()
    {
        _turfTileMap = new TurfTileMap { Name = "TurfTileMap" };
        AddChild(_turfTileMap);
    }

    public TurfCell GetOrCreateCell(Vector2I cell)
    {
        if (!_cells.TryGetValue(cell, out var turfCell))
        {
            turfCell = new TurfCell();
            _cells[cell] = turfCell;
        }
        return turfCell;
    }

    public TurfCell? GetCell(Vector2I cell) => _cells.GetValueOrDefault(cell);

    // Assigns the turf AND pushes/keeps its tile live on the TurfTileMap -
    // the fix for the old MapBootstrap-hardcoded-sprites gap: mutating a
    // turf (SetTurf again, or the turf raising IconChanged after damage)
    // now always shows up on screen, whether the turf came from map
    // authoring or a future DMM load.
    public void SetTurf(Vector2I cell, Turf turf)
    {
        var turfCell = GetOrCreateCell(cell);

        if (_turfIconHandlers.TryGetValue(cell, out var previousHandler) && turfCell.Turf != null)
        {
            turfCell.Turf.IconChanged -= previousHandler;
        }

        turfCell.Turf = turf;

        void Handler() => _turfTileMap?.SetCellTurf(cell, turf);
        turf.IconChanged += Handler;
        _turfIconHandlers[cell] = Handler;

        Handler();
    }

    public void SetArea(Vector2I cell, GameArea area) => GetOrCreateCell(cell).Area = area;

    // An unmapped cell (no TurfCell created yet) is treated as passable, not
    // blocked - true out-of-bounds handling belongs to whatever loads the
    // map, not to this default.
    public bool IsDense(Vector2I cell) => GetCell(cell)?.Turf?.IsDense ?? false;

    public bool BlocksLight(Vector2I cell) => GetCell(cell)?.Turf?.BlocksLight ?? false;

    public IReadOnlyList<MovableAtom> GetOccupants(Vector2I cell)
        => (IReadOnlyList<MovableAtom>?)GetCell(cell)?.Occupants ?? Array.Empty<MovableAtom>();

    // Every movable currently occupying any cell, across the whole map - used
    // for late-join world-state catch-up (a joining peer's map load only
    // recreates scene-authored defaults, so anything that's since moved,
    // appeared, or disappeared needs an explicit replay - see
    // Item.ReplayGroundStateTo).
    public IEnumerable<MovableAtom> GetAllOccupants()
    {
        foreach (var cell in _cells.Values)
        {
            foreach (var occupant in cell.Occupants)
            {
                yield return occupant;
            }
        }
    }

    public bool IsAdjacent(Vector2I a, Vector2I b)
    {
        if (a == b) return false;
        var d = a - b;
        return Mathf.Abs(d.X) <= 1 && Mathf.Abs(d.Y) <= 1;
    }

    // The single authoritative entry point for moving a movable between
    // cells - keeps occupancy lists and the movable's own GridCell in sync.
    // Both MovementController backends go through this rather than touching
    // occupancy or GridCell directly.
    public void MoveOccupant(MovableAtom movable, Vector2I from, Vector2I to)
    {
        if (from == to) return;

        GetCell(from)?.Occupants.Remove(movable);

        var destination = GetOrCreateCell(to);
        if (!destination.Occupants.Contains(movable))
        {
            destination.Occupants.Add(movable);
        }

        movable.SetGridCell(to);
    }

    // First-time placement (spawn) - there's no prior cell to remove the
    // movable from, unlike MoveOccupant. Safe to call even if the movable
    // already has a stale GridCell from before it entered the world.
    public void PlaceOccupant(MovableAtom movable, Vector2I at)
    {
        var destination = GetOrCreateCell(at);
        if (!destination.Occupants.Contains(movable))
        {
            destination.Occupants.Add(movable);
        }

        movable.SetGridCell(at);
    }

    // The inverse of PlaceOccupant - taking something out of the world
    // entirely (picked up into an inventory, deleted) rather than moving it
    // to another cell.
    public void RemoveOccupant(MovableAtom movable, Vector2I from)
        => GetCell(from)?.Occupants.Remove(movable);
}
