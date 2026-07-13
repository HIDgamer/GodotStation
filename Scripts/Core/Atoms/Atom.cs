using Godot;

namespace GodotStation.Core.Atoms;

// Base for anything atom-like that's a real scene node (world objects/mobs).
// Turf/area implement IAtom directly instead of extending this - see
// IAtom's header comment for why.
public abstract partial class Atom : Node2D, IAtom
{
    [Export] public string AtomName { get; set; } = "";
    [Export] public string Description { get; set; } = "";
    [Export] public float Integrity { get; set; } = 100f;
    [Export] public float MaxIntegrity { get; set; } = 100f;

    [Signal] public delegate void IntegrityChangedEventHandler(float newIntegrity, float maxIntegrity);
    [Signal] public delegate void DestroyedEventHandler();

    private bool _destroyed;

    public virtual string Examine()
        => string.IsNullOrEmpty(Description) ? AtomName : $"{AtomName}\n{Description}";

    public virtual void ApplyDamage(float amount)
    {
        if (amount <= 0f || _destroyed) return;

        Integrity = Mathf.Max(0f, Integrity - amount);
        EmitSignal(SignalName.IntegrityChanged, Integrity, MaxIntegrity);

        if (Integrity <= 0f) Destroy();
    }

    public void Destroy()
    {
        if (_destroyed) return;
        _destroyed = true;
        EmitSignal(SignalName.Destroyed);
        OnDestroyed();
    }

    // Override for cleanup beyond the Destroyed signal (drop contents, spawn
    // debris, etc.) - the base class only handles the integrity/signal bookkeeping.
    protected virtual void OnDestroyed() { }
}
