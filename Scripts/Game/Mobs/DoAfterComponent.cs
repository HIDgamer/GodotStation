using System;
using Godot;

namespace GodotStation.Game.Mobs;

// SS13-style "do-after": a timed action that cancels if the mob moves too
// far or gets incapacitated mid-way (surgery steps, defusing, climbing...).
// Ported from the old prototype. Connection rebuild: IMobSystem ->
// IMobComponent; the old hardcoded-uid progress-bar animation was dropped
// (that uid pointed at a deleted asset) - DoAfterStarted/Completed/
// Cancelled signals are the hook for whatever progress visual the HUD
// grows later.
public partial class DoAfterComponent : Node, IMobComponent
{
    private const float MaxMoveDistance = 16f;

    [Signal] public delegate void DoAfterStartedEventHandler(float duration);
    [Signal] public delegate void DoAfterCompletedEventHandler();
    [Signal] public delegate void DoAfterCancelledEventHandler(string reason);

    private Mob? _owner;
    private MobStateSystem? _mobState;
    private bool _active;
    private float _timer;
    private float _duration;
    private Action? _onComplete;
    private Action? _onCancel;
    private Vector2 _startPosition;

    public void Initialize(Mob mob)
    {
        _owner = mob;
        _mobState = mob.GetMobComponent<MobStateSystem>();
    }

    public void Cleanup() => Cancel("Component removed");

    public override void _Process(double delta)
    {
        if (!_active || _owner == null) return;

        if (_owner.GlobalPosition.DistanceTo(_startPosition) > MaxMoveDistance)
        {
            Cancel("Moved too far");
            return;
        }

        if (_mobState?.IsIncapacitated() == true)
        {
            Cancel("Incapacitated");
            return;
        }

        _timer += (float)delta;
        if (_timer >= _duration) Complete();
    }

    public bool StartAction(float duration, Action onComplete, Action? onCancel = null)
    {
        if (_active || _owner == null) return false;

        _active = true;
        _timer = 0f;
        _duration = duration;
        _onComplete = onComplete;
        _onCancel = onCancel;
        _startPosition = _owner.GlobalPosition;

        EmitSignal(SignalName.DoAfterStarted, duration);
        return true;
    }

    public void Cancel(string reason = "")
    {
        if (!_active) return;
        _active = false;
        _onCancel?.Invoke();
        EmitSignal(SignalName.DoAfterCancelled, reason);
    }

    private void Complete()
    {
        if (!_active) return;
        _active = false;
        _onComplete?.Invoke();
        EmitSignal(SignalName.DoAfterCompleted);
    }

    public bool IsDoingAction() => _active;
    public float GetProgress() => _active ? _timer / _duration : 0f;
}
