using System;
using Godot;
using GodotStation.Core.Subsystems;

namespace GodotStation.Core.Diagnostics;

// Records what happens during a round to a log file on disk, so verifying a
// change means reading that file instead of someone manually playing,
// watching, and narrating every event back over chat. Any system can call
// Log(category, message) at whatever point in its own logic is worth
// recording - this isn't a universal call-tracer (that would be noise, not
// signal, and prohibitively invasive to instrument by hand) but a growing,
// curated record of the events that actually matter: connections, spawns,
// item state changes, health/state changes, RPCs worth knowing about,
// errors. Add a Log() call at the point of change whenever a new system
// lands, the same way Item.cs's DoPlaceInWorld/DoRemoveFromWorld already do.
//
// Writes each line to disk immediately rather than buffering until the round
// formally ends: nothing currently calls TickerSubsystem.EndRound() (no
// round-end trigger exists yet), and even once one does, the two ways this
// project actually gets stopped in practice - the editor's Stop button, and
// force-killed headless test processes (see PORT_ROADMAP.md's Phase 1 entry
// on --quit-after corrupting the resource cache) - both kill the process
// outright rather than closing it gracefully. A buffer-until-the-end design
// would lose the entire log on both of those. Per-line writes mean the file
// on disk is always current up to whatever last happened, no matter how the
// process ends.
public partial class RoundLogger : Node
{
    private FileAccess? _file;
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
            StartRecording();
        }
        else if (previous == RoundState.Playing)
        {
            var duration = (DateTime.UtcNow - _roundStartUtc).TotalSeconds;
            Log("ROUND", $"Round ended after {duration:F1}s (state -> {next})");
            StopRecording();
        }
    }

    private void StartRecording()
    {
        _roundStartUtc = DateTime.UtcNow;

        const string dir = "user://round_logs";
        DirAccess.MakeDirRecursiveAbsolute(dir);
        var path = $"{dir}/round_{_roundStartUtc:yyyyMMdd_HHmmss}.log";

        _file = FileAccess.Open(path, FileAccess.ModeFlags.Write);
        if (_file == null)
        {
            GD.PrintErr($"[RoundLogger] Failed to open {path} for writing: {FileAccess.GetOpenError()}");
            return;
        }

        _recording = true;
        GD.Print($"[RoundLogger] Recording to {ProjectSettings.GlobalizePath(path)}");
        Log("ROUND", $"Round started (server={Multiplayer.IsServer()}, peer_id={Multiplayer.GetUniqueId()})");
    }

    private void StopRecording()
    {
        _recording = false;
        _file?.Dispose();
        _file = null;
    }

    // Safe to call even when no round is active or this node hasn't finished
    // _Ready() yet (e.g. very early startup logging) - it just also prints
    // to the console either way, matching every other subsystem's own
    // GD.Print convention, so nothing is lost even when not recording.
    public void Log(string category, string message)
    {
        var line = $"[{DateTime.UtcNow:HH:mm:ss.fff}] [{category}] {message}";
        if (_recording && _file != null)
        {
            _file.StoreLine(line);
            _file.Flush();
        }
        GD.Print(line);
    }
}
