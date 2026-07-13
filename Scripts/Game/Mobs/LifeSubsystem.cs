using System.Collections.Generic;
using Godot;
using GodotStation.Core.Subsystems;

namespace GodotStation.Game.Mobs;

// Drives all per-mob periodic ticking (health regen/decay, fire stacks,
// medical procedures...) - the SubsystemManager-native replacement for the
// old prototype's Scheduler/ISchedulable registrations. Mob components
// implementing ILifeTick get called at their own declared interval; this
// subsystem itself ticks fast (0.25s) and accumulates per-entry, so a 0.5s
// medical tick and a 1s health tick coexist without separate subsystems.
//
// MainThread affinity: life ticks touch nodes/signals directly. If a future
// profile shows this heavy at scale, individual computations can move to
// worker dispatch with results marshaled back - not warranted yet.
public sealed class LifeSubsystem : IGameSubsystem
{
    private sealed class Entry
    {
        public required ILifeTick Target;
        public double Accumulated;
    }

    private readonly List<Entry> _entries = new();

    public string Name => "Life";
    public double TickIntervalSeconds => 0.25;
    public SubsystemThreadAffinity ThreadAffinity => SubsystemThreadAffinity.MainThread;
    public int Priority => 0;

    public void Initialize() { }
    public void Shutdown() { }

    public void Register(ILifeTick target)
    {
        foreach (var entry in _entries)
        {
            if (entry.Target == target) return;
        }
        _entries.Add(new Entry { Target = target });
    }

    public void Unregister(ILifeTick target)
        => _entries.RemoveAll(e => e.Target == target);

    public void Tick(double delta)
    {
        // Iterate backwards so a component unregistering itself mid-tick
        // (e.g. on death cleanup) can't skip or double-tick neighbors.
        for (var i = _entries.Count - 1; i >= 0; i--)
        {
            var entry = _entries[i];

            // Godot-object targets that got freed without Cleanup() are
            // dropped rather than ticked into a disposed-object crash.
            if (entry.Target is GodotObject godotObject && !GodotObject.IsInstanceValid(godotObject))
            {
                _entries.RemoveAt(i);
                continue;
            }

            entry.Accumulated += delta;
            if (entry.Accumulated < entry.Target.LifeTickIntervalSeconds) continue;

            var tickDelta = entry.Accumulated;
            entry.Accumulated = 0;
            entry.Target.LifeTick(tickDelta);
        }
    }
}
