using System;
using System.Collections.Concurrent;
using Godot;

namespace GodotStation.Core.Subsystems;

// Deferred, budget-limited cleanup queue. Godot's own QueueFree() already
// defers node removal safely - this exists for cleanup work that's more than
// "free this node" (unregistering from WorldGrid, unsubscribing signals,
// releasing pooled resources) and where doing many of them in one frame
// would spike it. Conceptually mirrors ucfss13's garbage.dm qdel queue,
// without reimplementing memory GC we already get for free from .NET.
public sealed class GarbageSubsystem : IGameSubsystem
{
    private const int MaxPerTick = 64;

    private readonly ConcurrentQueue<Action> _pending = new();

    public string Name => "Garbage";
    public double TickIntervalSeconds => 0.1;
    public SubsystemThreadAffinity ThreadAffinity => SubsystemThreadAffinity.MainThread;
    public int Priority => -1000;

    public void Initialize() { }
    public void Shutdown() { }

    public void Enqueue(Action cleanup) => _pending.Enqueue(cleanup);

    public void Tick(double delta)
    {
        var processed = 0;
        while (processed < MaxPerTick && _pending.TryDequeue(out var cleanup))
        {
            try { cleanup(); }
            catch (Exception e) { GD.PrintErr($"[Garbage] cleanup action threw: {e}"); }
            processed++;
        }
    }
}
