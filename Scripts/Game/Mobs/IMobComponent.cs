namespace GodotStation.Game.Mobs;

// Contract for mob child-node components (health, inventory, movement,
// medical, fire...). Ported from the old prototype's IMobSystem - renamed
// to "component" to avoid clashing with the IGameSubsystem/SubsystemManager
// vocabulary, which means something else here (global tick domains, not
// per-mob parts).
//
// Components are child Nodes of a Mob; the Mob auto-collects anything
// implementing this on ready (and on later AddChild) and calls Initialize.
// Per-frame work stays in the component's own _Process/_PhysicsProcess;
// slow periodic work (health regen ticks, fire decay...) is driven by
// LifeSubsystem instead - components opt in by also implementing ILifeTick.
public interface IMobComponent
{
    void Initialize(Mob mob);

    void Cleanup();
}

// Opt-in periodic ticking for mob components, driven by LifeSubsystem at a
// per-component interval - the SubsystemManager-native replacement for the
// old prototype's Scheduler/ISchedulable registrations.
public interface ILifeTick
{
    // Seconds between ticks (e.g. health 1.0, medical 0.5).
    double LifeTickIntervalSeconds { get; }

    void LifeTick(double delta);
}
