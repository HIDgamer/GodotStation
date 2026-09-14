using System;

namespace GodotStation.Core.Atoms;

// A single grid cell's "floor/wall" identity. Deliberately not a Node - a
// map can have tens of thousands of these, so turf data lives in WorldGrid's
// TurfCell structure (Scripts/Core/World) and this is the shared identity/
// stat contract concrete turf types (floor, wall, ...) implement.
public abstract class Turf : IAtom
{
    public string AtomName { get; set; } = "";
    public string Description { get; set; } = "";
    public float Integrity { get; set; } = 100f;
    public float MaxIntegrity { get; set; } = 100f;

    // Whether movables can currently occupy this turf (a wall is not dense
    // when destroyed, etc.) - checked by WorldGrid before allowing entry.
    public virtual bool IsDense { get; protected set; }

    // Whether this turf blocks line-of-sight for the VisibilitySubsystem.
    public virtual bool BlocksLight { get; protected set; }

    // DMI sheet/state this turf renders as. WorldGrid owns the actual
    // Sprite2D (see WorldGrid.SetTurf/UpdateCellVisual) - a turf only needs
    // to say what it looks like and raise IconChanged when that changes, so
    // both map-authored and future DMM-loaded turfs render through the same
    // live path instead of a bootstrap script hardcoding sprites per cell.
    public string IconSheetPath { get; private set; } = "";
    public string IconState { get; private set; } = "";
    public event Action? IconChanged;

    protected void SetIcon(string sheetPath, string state)
    {
        IconSheetPath = sheetPath;
        IconState = state;
        IconChanged?.Invoke();
    }

    // Turf damage (wall demolition, etc.) - separate from Atom.ApplyDamage
    // since Turf isn't an Atom (no Node, no Destroyed signal), but the same
    // "clamp to 0, fire OnDestroyed once" shape.
    private bool _destroyed;
    public bool IsDestroyed => _destroyed;

    // What this cell becomes once destroyed (e.g. a wall reveals the floor
    // beneath it) - null means it has nothing to reveal (destruction is a
    // no-op for turfs that don't set this). A factory rather than a type, so
    // WorldGrid.SetTurf's subscriber (below) can build the replacement
    // without reflection. Matches ucfss13's own /turf/baseturfs concept,
    // simplified to a single layer since nothing here needs to dig through
    // more than one (e.g. floor-then-space) yet - extend to a real stack
    // if/when something does.
    public Func<Turf>? BaseTurf { get; protected set; }

    // Fired once, the tick Integrity reaches 0 - WorldGrid.SetTurf listens
    // for this to reveal BaseTurf automatically, so a turf never needs to
    // know about WorldGrid/its own cell to replace itself.
    public event Action? Destroyed;

    public virtual void ApplyDamage(float amount)
    {
        if (_destroyed || amount <= 0) return;

        Integrity = System.Math.Max(0, Integrity - amount);
        if (Integrity <= 0)
        {
            _destroyed = true;
            OnDestroyed();
            Destroyed?.Invoke();
        }
    }

    // Restores integrity - only meaningful before destruction (matches
    // ucfss13's own weld/nailgun repair, which only ever patches a damaged-
    // but-still-standing wall; once Integrity hits 0 the turf is replaced by
    // BaseTurf entirely, so there's nothing left on this cell to repair -
    // building a new wall there is construction, not repair).
    public virtual void Repair(float amount)
    {
        if (_destroyed || amount <= 0) return;
        Integrity = System.Math.Min(MaxIntegrity, Integrity + amount);
    }

    protected virtual void OnDestroyed() { }

    public virtual string Examine()
        => string.IsNullOrEmpty(Description) ? AtomName : $"{AtomName}\n{Description}";
}
