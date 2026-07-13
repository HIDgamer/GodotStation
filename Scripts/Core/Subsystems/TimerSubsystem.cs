using System;
using System.Collections.Generic;
using Godot;

namespace GodotStation.Core.Subsystems;

// Generic scheduled-callback engine - the foundation for status effect
// durations, cooldowns, and delayed actions. Mirrors ucfss13's timer.dm
// (a load-bearing utility subsystem almost everything else depends on),
// reimplemented as a plain callback scheduler rather than ported.
public sealed class TimerSubsystem : IGameSubsystem
{
    internal sealed class ScheduledCallback
    {
        public double FireAtSeconds;
        public Action Callback = null!;
        public bool Cancelled;
    }

    public readonly struct TimerHandle
    {
        private readonly ScheduledCallback _target;
        internal TimerHandle(ScheduledCallback target) => _target = target;
        public void Cancel() => _target.Cancelled = true;
    }

    private readonly List<ScheduledCallback> _scheduled = new();
    private double _elapsed;

    public string Name => "Timer";
    public double TickIntervalSeconds => 0.05;
    public SubsystemThreadAffinity ThreadAffinity => SubsystemThreadAffinity.MainThread;
    public int Priority => -900;

    public void Initialize() { }
    public void Shutdown() { }

    public TimerHandle ScheduleAfter(double seconds, Action callback)
    {
        var entry = new ScheduledCallback { FireAtSeconds = _elapsed + seconds, Callback = callback };
        _scheduled.Add(entry);
        return new TimerHandle(entry);
    }

    public void Tick(double delta)
    {
        _elapsed += delta;
        for (var i = _scheduled.Count - 1; i >= 0; i--)
        {
            var entry = _scheduled[i];
            if (entry.Cancelled) { _scheduled.RemoveAt(i); continue; }
            if (_elapsed < entry.FireAtSeconds) continue;

            _scheduled.RemoveAt(i);
            try { entry.Callback(); }
            catch (Exception e) { GD.PrintErr($"[Timer] scheduled callback threw: {e}"); }
        }
    }
}
