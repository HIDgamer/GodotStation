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

    public virtual void ApplyDamage(float amount)
    {
        if (_destroyed || amount <= 0) return;

        Integrity = System.Math.Max(0, Integrity - amount);
        if (Integrity <= 0)
        {
            _destroyed = true;
            OnDestroyed();
        }
    }

    protected virtual void OnDestroyed() { }

    public virtual string Examine()
        => string.IsNullOrEmpty(Description) ? AtomName : $"{AtomName}\n{Description}";
}
