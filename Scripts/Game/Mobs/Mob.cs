using System.Collections.Generic;
using Godot;
using GodotStation.Core.Atoms;

namespace GodotStation.Game.Mobs;

// Base for anything that can be "piloted" - a player character, a xeno, an
// NPC. Faction-specific behavior lives in Game.Mobs.Living/.Dead/.NewPlayer
// subclasses, not here - this only holds what's true of every mob.
//
// Component auto-collection is ported from the old prototype's Mob root:
// any child Node implementing IMobComponent (at any depth) is registered
// and Initialize()d automatically on ready and whenever added later, so
// mob scenes compose capabilities by just parenting component nodes -
// nothing needs manual wiring. The old CharacterBody2D base, physics-body
// fields, and authority-from-node-name logic were deliberately NOT ported
// (movement is grid/WorldGrid-based and authority is server-side, per the
// current architecture).
public abstract partial class Mob : MovableAtom
{
    [Signal] public delegate void DiedEventHandler();

    // Whether this mob blocks other movables from sharing its cell. Not yet
    // enforced by WorldGrid.IsDense (turf-only today) - mob-vs-mob blocking
    // becomes real when the interaction layer consults occupant density.
    [Export] public bool Density { get; set; } = true;

    [Export] public bool IsGhost { get; set; }

    public bool IsDead { get; private set; }

    private readonly List<IMobComponent> _components = new();

    public override void _Ready()
    {
        RegisterComponentsRecursive(this);
        ChildEnteredTree += child => RegisterComponentsRecursive(child);
    }

    public T? GetMobComponent<T>() where T : class
    {
        foreach (var component in _components)
        {
            if (component is T typed) return typed;
        }
        return null;
    }

    public IReadOnlyList<IMobComponent> Components => _components;

    private void RegisterComponentsRecursive(Node root)
    {
        if (root != this && root is IMobComponent rootComponent && !_components.Contains(rootComponent))
        {
            _components.Add(rootComponent);
            rootComponent.Initialize(this);
        }

        foreach (var child in root.GetChildren())
        {
            RegisterComponentsRecursive(child);
        }
    }

    public override void _ExitTree()
    {
        foreach (var component in _components)
        {
            component.Cleanup();
        }
        _components.Clear();
    }

    protected override void OnDestroyed()
    {
        base.OnDestroyed();
        if (IsDead) return;
        IsDead = true;
        EmitSignal(SignalName.Died);
    }
}
