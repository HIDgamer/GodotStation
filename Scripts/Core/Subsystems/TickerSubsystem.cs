using System;
using Godot;

namespace GodotStation.Core.Subsystems;

public enum RoundState
{
    PreRound,   // Lobby - players connected, round hasn't started
    Playing,    // Round is live
    PostRound,  // Round ended, showing results before next PreRound
}

// Owns round lifecycle and nothing else - no map/spawn/objective logic lives
// here. Other systems (NetworkManager, spawn flow, future objective systems)
// react to StateChanged rather than this subsystem reaching into them, so new
// round-flow behavior is always additive here rather than a cross-cutting
// change (see the M2 roadmap's parity-maintenance rationale).
public sealed class TickerSubsystem : IGameSubsystem
{
    public event Action<RoundState, RoundState>? StateChanged;

    public RoundState State { get; private set; } = RoundState.PreRound;
    public double RoundElapsedSeconds { get; private set; }

    public string Name => "Ticker";
    public double TickIntervalSeconds => 1.0;
    public SubsystemThreadAffinity ThreadAffinity => SubsystemThreadAffinity.MainThread;
    public int Priority => -900;

    public void Initialize() { }
    public void Shutdown() { }

    public void Tick(double delta)
    {
        if (State == RoundState.Playing)
        {
            RoundElapsedSeconds += delta;
        }
    }

    public void StartRound()
    {
        if (State != RoundState.PreRound)
        {
            GD.PrintErr($"[Ticker] StartRound() called while State={State}; ignoring.");
            return;
        }

        RoundElapsedSeconds = 0;
        SetState(RoundState.Playing);
    }

    public void EndRound()
    {
        if (State != RoundState.Playing)
        {
            GD.PrintErr($"[Ticker] EndRound() called while State={State}; ignoring.");
            return;
        }

        SetState(RoundState.PostRound);
    }

    // Returns to PreRound for the next round to be started - separate from
    // EndRound() so a results screen can hold PostRound for as long as it wants.
    public void ResetToLobby()
    {
        RoundElapsedSeconds = 0;
        SetState(RoundState.PreRound);
    }

    private void SetState(RoundState next)
    {
        var previous = State;
        State = next;
        StateChanged?.Invoke(previous, next);
    }
}
