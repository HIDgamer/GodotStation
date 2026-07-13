using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace GodotStation.Core.Subsystems;

// Central tick dispatcher for every ongoing-logic domain in the game
// (machinery, mob upkeep, xeno AI, power, timers, garbage collection...).
// One IGameSubsystem per domain, each declaring its own tick rate and
// thread affinity - see the M2 roadmap's Foundational Architecture section
// for why this exists and how domains are expected to map onto it.
public partial class SubsystemManager : Node
{
    // A MainThread subsystem whose Tick() takes longer than this is logged as
    // a slow-tick warning. Not a hard timeout (C# can't preempt a running
    // synchronous call cheaply) - just an early-warning signal.
    private const double SlowTickWarningSeconds = 0.25;

    // Consecutive failures (exceptions or slow ticks) before a subsystem is
    // disabled rather than nuking the whole manager loop.
    private const int MaxConsecutiveFailures = 5;

    private sealed class Entry
    {
        public required IGameSubsystem Subsystem;
        public double Accumulated;
        public int ConsecutiveFailures;
        public bool Disabled;
        public Thread? WorkerThread;
        public volatile bool WorkerShouldStop;
    }

    private readonly List<Entry> _mainThreadEntries = new();
    private readonly List<Entry> _workerEntries = new();
    private readonly List<Entry> _workerPoolEntries = new();
    private readonly Dictionary<Type, IGameSubsystem> _byType = new();
    private readonly ConcurrentQueue<Action> _mainThreadCallbacks = new();

    public override void _Ready()
    {
        // Load-bearing utility subsystems first - everything else (deferred
        // cleanup, scheduled callbacks/status effects/cooldowns) depends on
        // these existing before any content subsystem ticks.
        Register(new GarbageSubsystem());
        Register(new TimerSubsystem());
        Register(new TickerSubsystem());
        Register(new Game.Mobs.LifeSubsystem());
    }

    public override void _ExitTree()
    {
        foreach (var entry in _mainThreadEntries.Concat(_workerEntries).Concat(_workerPoolEntries))
        {
            StopWorkerIfAny(entry);
            SafeShutdown(entry);
        }
    }

    public void Register(IGameSubsystem subsystem)
    {
        var entry = new Entry { Subsystem = subsystem };
        _byType[subsystem.GetType()] = subsystem;

        try
        {
            subsystem.Initialize();
        }
        catch (Exception e)
        {
            GD.PrintErr($"[SubsystemManager] '{subsystem.Name}' threw during Initialize(): {e}");
            entry.Disabled = true;
        }

        switch (subsystem.ThreadAffinity)
        {
            case SubsystemThreadAffinity.MainThread:
                _mainThreadEntries.Add(entry);
                _mainThreadEntries.Sort((a, b) => a.Subsystem.Priority.CompareTo(b.Subsystem.Priority));
                break;
            case SubsystemThreadAffinity.Worker:
                _workerEntries.Add(entry);
                if (!entry.Disabled) StartWorkerThread(entry);
                break;
            case SubsystemThreadAffinity.WorkerPool:
                _workerPoolEntries.Add(entry);
                break;
        }
    }

    // Thread-safe hand-off for Worker/WorkerPool subsystems that computed a
    // result off the main thread and need to apply it to the scene tree.
    // Queued callbacks run at the start of the next main-thread tick pass.
    public void RunOnMainThread(Action callback) => _mainThreadCallbacks.Enqueue(callback);

    public T? GetSubsystem<T>() where T : class, IGameSubsystem
        => _byType.TryGetValue(typeof(T), out var s) ? s as T : null;

    public override void _PhysicsProcess(double delta)
    {
        while (_mainThreadCallbacks.TryDequeue(out var callback))
        {
            try { callback(); }
            catch (Exception e) { GD.PrintErr($"[SubsystemManager] main-thread callback threw: {e}"); }
        }

        foreach (var entry in _mainThreadEntries)
        {
            if (entry.Disabled) continue;
            TickIfDue(entry, delta);
        }

        foreach (var entry in _workerPoolEntries)
        {
            if (entry.Disabled) continue;
            entry.Accumulated += delta;
            if (entry.Accumulated < entry.Subsystem.TickIntervalSeconds) continue;
            entry.Accumulated -= entry.Subsystem.TickIntervalSeconds;

            var capturedDelta = entry.Subsystem.TickIntervalSeconds;
            Task.Run(() => TickWorker(entry, capturedDelta));
        }
    }

    private void TickIfDue(Entry entry, double delta)
    {
        entry.Accumulated += delta;
        if (entry.Accumulated < entry.Subsystem.TickIntervalSeconds) return;
        var tickDelta = entry.Accumulated;
        entry.Accumulated -= entry.Subsystem.TickIntervalSeconds;

        var start = Time.GetTicksMsec();
        try
        {
            entry.Subsystem.Tick(tickDelta);
            entry.ConsecutiveFailures = 0;
        }
        catch (Exception e)
        {
            HandleFailure(entry, $"threw during Tick(): {e}");
            return;
        }

        var elapsedSeconds = (Time.GetTicksMsec() - start) / 1000.0;
        if (elapsedSeconds > SlowTickWarningSeconds)
        {
            GD.PrintErr($"[SubsystemManager] '{entry.Subsystem.Name}' took {elapsedSeconds:F2}s to tick (budget {SlowTickWarningSeconds:F2}s).");
        }
    }

    private void StartWorkerThread(Entry entry)
    {
        entry.WorkerThread = new Thread(() =>
        {
            while (!entry.WorkerShouldStop && !entry.Disabled)
            {
                var start = Time.GetTicksMsec();
                try
                {
                    entry.Subsystem.Tick(entry.Subsystem.TickIntervalSeconds);
                    entry.ConsecutiveFailures = 0;
                }
                catch (Exception e)
                {
                    HandleFailure(entry, $"threw on worker thread: {e}");
                    if (entry.Disabled) break;
                }

                var elapsedMs = (long)(Time.GetTicksMsec() - start);
                var sleepMs = (long)(entry.Subsystem.TickIntervalSeconds * 1000) - elapsedMs;
                if (sleepMs > 0) Thread.Sleep((int)sleepMs);
            }
        })
        {
            IsBackground = true,
            Name = $"Subsystem-{entry.Subsystem.Name}",
        };
        entry.WorkerThread.Start();
    }

    private void TickWorker(Entry entry, double delta)
    {
        try
        {
            entry.Subsystem.Tick(delta);
            entry.ConsecutiveFailures = 0;
        }
        catch (Exception e)
        {
            HandleFailure(entry, $"threw on worker-pool task: {e}");
        }
    }

    private void HandleFailure(Entry entry, string message)
    {
        entry.ConsecutiveFailures++;
        GD.PrintErr($"[SubsystemManager] '{entry.Subsystem.Name}' {message} (failure {entry.ConsecutiveFailures}/{MaxConsecutiveFailures})");

        if (entry.ConsecutiveFailures < MaxConsecutiveFailures) return;

        GD.PrintErr($"[SubsystemManager] '{entry.Subsystem.Name}' exceeded consecutive failure limit - disabling.");
        entry.Disabled = true;
        StopWorkerIfAny(entry);
        SafeShutdown(entry);
    }

    private void StopWorkerIfAny(Entry entry)
    {
        entry.WorkerShouldStop = true;
        entry.WorkerThread?.Join(TimeSpan.FromSeconds(2));
    }

    private void SafeShutdown(Entry entry)
    {
        try { entry.Subsystem.Shutdown(); }
        catch (Exception e) { GD.PrintErr($"[SubsystemManager] '{entry.Subsystem.Name}' threw during Shutdown(): {e}"); }
    }
}
