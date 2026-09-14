using System;
using System.Collections.Generic;
using Godot;
using GodotStation.Core.Subsystems;

namespace GodotStation.Core.Diagnostics;

// Records what happens during a round and writes one structured log file when
// it ends, so verifying a change means reading that file instead of someone
// manually playing, watching, and narrating every event back over chat. Any
// system can call Log(category, message) at whatever point in its own logic
// is worth recording - this isn't a universal call-tracer (that would be
// noise, not signal, and prohibitively invasive to instrument by hand) but a
// growing, curated record of the events that actually matter: connections,
// spawns, item state changes, health/state changes, RPCs worth knowing
// about, errors. Add a Log() call at the point of change whenever a new
// system lands, the same way Item.cs's DoPlaceInWorld/DoRemoveFromWorld
// already do.
public partial class RoundLogger : Node
{
    private readonly List<string> _entries = new();
    private DateTime _roundStartUtc;
    private bool _recording;

    public override void _Ready()
    {
        var subsystems = GetNodeOrNull<SubsystemManager>("/root/SubsystemManager");
        var ticker = subsystems?.GetSubsystem<TickerSubsystem>();
        if (ticker != null)
        {
            ticker.StateChanged += OnRoundStateChanged;
        }
    }

    private void OnRoundStateChanged(RoundState previous, RoundState next)
    {
        if (next == RoundState.Playing)
        {
            _entries.Clear();
            _roundStartUtc = DateTime.UtcNow;
            _recording = true;
            Log("ROUND", $"Round started (server={Multiplayer.IsServer()}, peer_id={Multiplayer.GetUniqueId()})");
        }
        else if (previous == RoundState.Playing)
        {
            var duration = (DateTime.UtcNow - _roundStartUtc).TotalSeconds;
            Log("ROUND", $"Round ended after {duration:F1}s (state -> {next})");
            FlushToFile();
            _recording = false;
        }
    }

    // Safe to call even when no round is active or this node hasn't finished
    // _Ready() yet (e.g. very early startup logging) - it just also prints
    // to the console either way, matching every other subsystem's own
    // GD.Print convention, so nothing is lost even when not recording.
    public void Log(string category, string message)
    {
        var line = $"[{DateTime.UtcNow:HH:mm:ss.fff}] [{category}] {message}";
        if (_recording)
        {
            _entries.Add(line);
        }
        GD.Print(line);
    }

    private void FlushToFile()
    {
        const string dir = "user://round_logs";
        DirAccess.MakeDirRecursiveAbsolute(dir);
        var path = $"{dir}/round_{_roundStartUtc:yyyyMMdd_HHmmss}.log";
        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Write);
        if (file == null)
        {
            GD.PrintErr($"[RoundLogger] Failed to open {path} for writing: {FileAccess.GetOpenError()}");
            return;
        }
        foreach (var line in _entries)
        {
            file.StoreLine(line);
        }
        GD.Print($"[RoundLogger] Wrote {_entries.Count} events to {ProjectSettings.GlobalizePath(path)}");
    }
}
