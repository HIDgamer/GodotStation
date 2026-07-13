using Godot;
using GodotStation.Core.Subsystems;

namespace GodotStation.Game.Mobs.Health;

// Per-mob burning status effect, ported from the old prototype (its own
// original code). Connection rebuild notes vs. the old version:
//  - Scheduler/ISchedulable -> LifeSubsystem/ILifeTick (same 1s interval
//    the old SchedulerUpdateInterval used), matching HealthSystem's own
//    rebuild - fire damage is another periodic damage-over-time source and
//    lives alongside it under Mobs/Health.
//  - The old AnyPeer sync RPC is gone: server-authoritative only, mutators
//    no-op off-server, state changes go out as plain Godot signals.
//  - ShowChatBubble -> StatusMessage signal, same pattern HealthSystem uses
//    (PlayerMob routes it to ChatManager as a private system message).
//  - Damage lands on the sibling HealthSystem via Mob.GetMobComponent
//    instead of a node-path lookup.
public partial class FireSystem : Node, IMobComponent, ILifeTick
{
    [Export] public float MaxFireStacks = 10f;
    [Export] public float FireDamagePerStack = 2.0f;
    [Export] public float FireStackDecayRate = 0.5f;
    [Export] public float FireResistance;
    [Export] public float WaterExtinguishRate = 5.0f;

    [Signal] public delegate void FireStateChangedEventHandler(bool isOnFire);
    [Signal] public delegate void FireStacksChangedEventHandler(float fireStacks);
    [Signal] public delegate void StatusMessageEventHandler(string text);

    public double LifeTickIntervalSeconds => 1.0;

    private Mob? _mob;
    private bool _isProcessing;
    private float _fireStacks;
    private bool _isOnFire;

    public void Initialize(Mob mob)
    {
        _mob = mob;
        _fireStacks = 0f;
        _isOnFire = false;
        _isProcessing = true;

        GetNodeOrNull<SubsystemManager>("/root/SubsystemManager")
            ?.GetSubsystem<LifeSubsystem>()?.Register(this);
    }

    public void Cleanup()
    {
        _isProcessing = false;
        GetNodeOrNull<SubsystemManager>("/root/SubsystemManager")
            ?.GetSubsystem<LifeSubsystem>()?.Unregister(this);
    }

    public void LifeTick(double delta)
    {
        if (!_isProcessing || _mob == null || !Multiplayer.IsServer()) return;
        UpdateFire((float)delta);
    }

    private void UpdateFire(float delta)
    {
        if (_fireStacks > 0)
        {
            _fireStacks = Mathf.Max(0, _fireStacks - FireStackDecayRate * delta);
            EmitSignal(SignalName.FireStacksChanged, _fireStacks);
        }

        var shouldBeOnFire = _fireStacks > 0;
        if (_isOnFire != shouldBeOnFire)
        {
            _isOnFire = shouldBeOnFire;
            EmitSignal(SignalName.FireStateChanged, _isOnFire);
            EmitSignal(SignalName.StatusMessage, _isOnFire ? "You are on fire!" : "You are no longer on fire.");
        }

        if (_isOnFire) ApplyFireDamage();
    }

    private void ApplyFireDamage()
    {
        var health = _mob?.GetMobComponent<HealthSystem>();
        if (health == null) return;

        var damage = FireDamagePerStack * _fireStacks * (1.0f - FireResistance);
        health.ApplyDamage(DamageType.Burn, damage, "Fire");
    }

    public void TryIgnite(float fireStacks)
    {
        if (!Multiplayer.IsServer() || fireStacks <= 0) return;

        _fireStacks = Mathf.Min(_fireStacks + fireStacks, MaxFireStacks);
        EmitSignal(SignalName.FireStacksChanged, _fireStacks);

        if (!_isOnFire)
        {
            _isOnFire = true;
            EmitSignal(SignalName.FireStateChanged, _isOnFire);
            EmitSignal(SignalName.StatusMessage, "You are on fire!");
        }
    }

    public void Extinguish()
    {
        if (!Multiplayer.IsServer() || !_isOnFire) return;

        _fireStacks = 0f;
        _isOnFire = false;
        EmitSignal(SignalName.FireStateChanged, _isOnFire);
        EmitSignal(SignalName.FireStacksChanged, _fireStacks);
        EmitSignal(SignalName.StatusMessage, "You have been extinguished.");
    }

    public void ApplyWaterExtinguish(float waterAmount)
    {
        if (!Multiplayer.IsServer() || _fireStacks <= 0) return;

        _fireStacks = Mathf.Max(0, _fireStacks - waterAmount * WaterExtinguishRate);
        EmitSignal(SignalName.FireStacksChanged, _fireStacks);

        if (_fireStacks <= 0 && _isOnFire)
        {
            _isOnFire = false;
            EmitSignal(SignalName.FireStateChanged, _isOnFire);
            EmitSignal(SignalName.StatusMessage, "You have been extinguished.");
        }
    }

    public void SetFireResistance(float resistance) => FireResistance = Mathf.Clamp(resistance, 0.0f, 1.0f);

    public bool IsOnFire() => _isOnFire;
    public float GetFireStacks() => _fireStacks;
    public float GetMaxFireStacks() => MaxFireStacks;
}
