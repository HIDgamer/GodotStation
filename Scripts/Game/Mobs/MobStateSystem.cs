using Godot;
using GodotStation.Core.World;
using GodotStation.Game.Mobs.Health;

namespace GodotStation.Game.Mobs;

public enum MobState { Standing, Prone, Sleeping, Critical, Dead, Stunned, Grabbed }

// Coarse HUD-facing consciousness bucket, kept from the pre-reclamation
// HealthComponent because PlayerMob's frozen Hud ABI ships it to clients.
// Derived from MobState via MobStateSystem.ToConsciousState.
public enum ConsciousState { Conscious, Unconscious, Dead }

// Body-position/consciousness state machine, ported from the old prototype.
// Connection rebuild: HealthSystem signals wire up in Initialize (component
// auto-collection order isn't guaranteed, so it defers if health isn't
// registered yet); sync RPCs dropped (server-side only - PlayerMob
// broadcasts the derived ConsciousState via its frozen Hud ABI); the old
// SpriteSystem prone-rotation call becomes a ProneChanged signal for the
// mob's visual layer (placeholder rotation now, MobAppearance later).
public partial class MobStateSystem : Node, IMobComponent
{
    [Signal] public delegate void StateChangedEventHandler(int newState, int oldState);
    [Signal] public delegate void ProneChangedEventHandler(bool isProne);

    public MobState State { get; private set; } = MobState.Standing;

    private Mob? _mob;
    private float _stateTimer;
    private float _stateDuration;

    public void Initialize(Mob mob)
    {
        _mob = mob;

        var health = mob.GetMobComponent<HealthSystem>();
        if (health != null)
        {
            health.CriticalHealth += OnCriticalHealth;
            health.CriticalRecovered += OnCriticalRecovered;
            health.Death += OnDeath;
        }
        else
        {
            // HealthSystem may register after us - retry once the frame ends.
            CallDeferred(nameof(LateBindHealth));
        }
    }

    private void LateBindHealth()
    {
        var health = _mob?.GetMobComponent<HealthSystem>();
        if (health == null) return;
        health.CriticalHealth += OnCriticalHealth;
        health.CriticalRecovered += OnCriticalRecovered;
        health.Death += OnDeath;
    }

    public void Cleanup() { }

    public override void _Process(double delta)
    {
        if (_stateDuration <= 0 || !Multiplayer.IsServer()) return;

        _stateTimer += (float)delta;
        if (_stateTimer >= _stateDuration)
        {
            if (State == MobState.Stunned) SetState(MobState.Standing);
            _stateDuration = 0;
            _stateTimer = 0;
        }
    }

    public void SetState(MobState newState, float duration = 0f)
    {
        if (State == newState) return;
        if (State == MobState.Dead) return; // death is terminal

        var oldState = State;
        State = newState;
        _stateDuration = duration;
        _stateTimer = 0f;

        EmitSignal(SignalName.StateChanged, (int)newState, (int)oldState);
        EmitSignal(SignalName.ProneChanged, IsProneLike(newState));
        ApplySpeedModifier(newState);
    }

    public void ForceProne()
    {
        if (State == MobState.Standing) SetState(MobState.Prone);
    }

    public void HelpUp()
    {
        if (State is MobState.Prone or MobState.Sleeping) SetState(MobState.Standing);
    }

    public void SetStunned(float duration)
    {
        if (State == MobState.Prone)
        {
            // Already down - just extend the timer rather than stand-then-stun.
            _stateDuration = duration;
            _stateTimer = 0f;
        }
        else
        {
            SetState(MobState.Stunned, duration);
        }
    }

    public static bool IsProneLike(MobState state)
        => state is MobState.Prone or MobState.Sleeping or MobState.Critical or MobState.Dead;

    public static ConsciousState ToConsciousState(MobState state) => state switch
    {
        MobState.Dead => ConsciousState.Dead,
        MobState.Critical or MobState.Sleeping => ConsciousState.Unconscious,
        _ => ConsciousState.Conscious,
    };

    public bool IsIncapacitated()
        => State is MobState.Sleeping or MobState.Critical or MobState.Dead or MobState.Stunned or MobState.Grabbed;

    private void OnCriticalHealth() => SetState(MobState.Critical);

    private void OnCriticalRecovered()
    {
        if (State == MobState.Critical) SetState(MobState.Prone);
    }

    private void OnDeath() => SetState(MobState.Dead);

    private void ApplySpeedModifier(MobState state)
    {
        var movement = _mob?.GetNodeOrNull<MovementController>("MovementController");
        if (movement == null) return;

        movement.StateSpeedMultiplier = state switch
        {
            MobState.Prone => 0.5f,
            MobState.Sleeping or MobState.Critical or MobState.Dead or MobState.Stunned or MobState.Grabbed => 0f,
            _ => 1f,
        };
    }
}
