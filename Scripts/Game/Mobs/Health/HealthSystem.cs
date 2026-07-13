using System;
using System.Collections.Generic;
using Godot;
using GodotStation.Core.Subsystems;
using GodotStation.Core.World;

namespace GodotStation.Game.Mobs.Health;

public enum DamageType { Brute, Burn, Toxin, Oxygen, Clone, Brain, HalLoss, Special }

public enum PainLevel { None, Mild, Discomforting, Moderate, Distressing, Severe, Horrible }

public enum StatusEffectType
{
    Stun, KnockDown, KnockOut, Daze, Slow, Superslow, Root,
    Sleeping, EyeBlur, EyeBlind, EarDeafness, Stutter, Drowsy,
}

public readonly struct DamageData
{
    public readonly DamageType Type;
    public readonly float Amount;
    public readonly string SourceName;

    public DamageData(DamageType type, float amount, string sourceName = "Unknown")
    {
        Type = type;
        Amount = amount;
        SourceName = sourceName;
    }
}

// Full SS13-style health model, ported from the old prototype (its own
// original code). Connection rebuild notes vs. the old version:
//  - Scheduler/ISchedulable -> LifeSubsystem/ILifeTick (periodic damage at
//    0.5s); cheap per-frame work (pain, regen, status timers) stays in
//    _Process.
//  - The old AnyPeer sync RPCs are gone: this runs server-authoritative
//    only, mutators no-op off-server, and all outward communication is
//    Godot signals. PlayerMob bridges those to its frozen Hud* RPC ABI -
//    this class knows nothing about networking.
//  - Chat-bubble feedback -> StatusMessage signal (PlayerMob routes it to
//    ChatManager as a private system message).
//  - Death -> Mob.Destroy(), driving the existing Atom Destroyed/Died flow.
public partial class HealthSystem : Node, IMobComponent, ILifeTick
{
    [Export] public float MaxHealth = 100f;
    [Export] public float MaxBruteDamage = 100f;
    [Export] public float MaxBurnDamage = 100f;
    [Export] public float MaxToxinDamage = 100f;
    [Export] public float MaxOxygenDamage = 100f;
    [Export] public float BaseRegenRate = 1.0f;
    [Export] public float RegenDelay = 5.0f;

    [Export] public float PainThresholdMild = 20f;
    [Export] public float PainThresholdDiscomforting = 30f;
    [Export] public float PainThresholdModerate = 40f;
    [Export] public float PainThresholdDistressing = 60f;
    [Export] public float PainThresholdSevere = 75f;
    [Export] public float PainThresholdHorrible = 85f;

    [Export] public float BruteResistance;
    [Export] public float BurnResistance;
    [Export] public float ToxinResistance;
    [Export] public float OxygenResistance;

    // Movement speed multipliers per pain tier (applied via
    // MovementController.SpeedMultiplier). Values <1 slow the mob down.
    [Export] public float PainSpeedMild = 1.0f;
    [Export] public float PainSpeedDiscomforting = 0.9f;
    [Export] public float PainSpeedModerate = 0.75f;
    [Export] public float PainSpeedDistressing = 0.6f;
    [Export] public float PainSpeedSevere = 0.4f;

    private const float BrutePainMultiplier = 1.0f;
    private const float BurnPainMultiplier = 1.2f;
    private const float ToxinPainMultiplier = 1.5f;
    private const float OxygenPainMultiplier = 1.0f;
    private const float CriticalHealthFraction = 0.25f;

    [Signal] public delegate void HealthChangedEventHandler(float currentHealth, float maxHealth);
    [Signal] public delegate void DamageTakenEventHandler(int damageType, float damageAmount, string sourceName, float remainingHealth);
    [Signal] public delegate void PainLevelChangedEventHandler(int newLevel, int oldLevel);
    [Signal] public delegate void CriticalHealthEventHandler();
    [Signal] public delegate void CriticalRecoveredEventHandler();
    [Signal] public delegate void DeathEventHandler();
    [Signal] public delegate void StatusMessageEventHandler(string text);

    public double LifeTickIntervalSeconds => 0.5;

    private Mob? _mob;
    private MovementController? _movement;
    private bool _isProcessing;

    private float _currentHealth;
    private float _currentBruteDamage;
    private float _currentBurnDamage;
    private float _currentToxinDamage;
    private float _currentOxygenDamage;
    private float _currentPainReduction;
    private float _timeSinceLastDamage;
    private PainLevel _currentPainLevel = PainLevel.None;
    private bool _isRegenerating;
    private bool _wasCritical;
    private bool _isDead;

    private float _oxygenAccumulator;
    private float _bleedAccumulator;
    private float _toxinAccumulator;

    // Status effect countdown timers, keyed by effect. The old prototype
    // used 13 separate float fields; a dictionary is the same behavior with
    // less repetition.
    private readonly Dictionary<StatusEffectType, float> _statusTimers = new();

    public void Initialize(Mob mob)
    {
        _mob = mob;
        _movement = mob.GetNodeOrNull<MovementController>("MovementController");
        InitializeHealth();
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

    private void InitializeHealth()
    {
        _currentHealth = MaxHealth;
        _currentBruteDamage = 0f;
        _currentBurnDamage = 0f;
        _currentToxinDamage = 0f;
        _currentOxygenDamage = 0f;
        _currentPainReduction = 0f;
        _timeSinceLastDamage = RegenDelay;
        _currentPainLevel = PainLevel.None;
        _wasCritical = false;
        _isDead = false;
        EmitSignal(SignalName.HealthChanged, _currentHealth, MaxHealth);
    }

    public override void _Process(double delta)
    {
        if (!_isProcessing || _mob == null || !Multiplayer.IsServer()) return;

        _timeSinceLastDamage += (float)delta;
        UpdatePainLevel();
        HandleRegeneration((float)delta);
        UpdateStatusTimers((float)delta);
        ApplyStatusEffects();
    }

    // Periodic damage-over-time (asphyxiation/bleeding/toxins), driven by
    // LifeSubsystem at 0.5s rather than every frame.
    public void LifeTick(double delta)
    {
        if (!_isProcessing || _mob == null || _isDead || !Multiplayer.IsServer()) return;
        ApplyPeriodicDamage((float)delta);
    }

    private void ApplyPeriodicDamage(float delta)
    {
        _oxygenAccumulator += delta;
        if (_oxygenAccumulator >= 1.0f && _currentOxygenDamage > 0)
        {
            ApplyDamage(DamageType.Oxygen, 2.0f * _oxygenAccumulator, "Asphyxiation");
            _oxygenAccumulator = 0f;
        }

        _bleedAccumulator += delta;
        if (_bleedAccumulator >= 0.5f && _currentBruteDamage > 0)
        {
            var brutePercentage = _currentBruteDamage / MaxBruteDamage;
            var bleedRate = 1.0f + brutePercentage * 4.0f;
            ApplyDamage(DamageType.Brute, bleedRate * _bleedAccumulator, "Bleeding");
            _bleedAccumulator = 0f;
        }

        _toxinAccumulator += delta;
        if (_toxinAccumulator >= 1.0f && _currentToxinDamage > 0)
        {
            var toxinPercentage = _currentToxinDamage / MaxToxinDamage;
            var damagePerSecond = 0.5f + toxinPercentage * 2.5f;
            ApplyDamage(DamageType.Toxin, damagePerSecond * _toxinAccumulator, "Toxin");
            _toxinAccumulator = 0f;
        }
    }

    public void ApplyDamage(DamageType type, float amount, string sourceName = "Unknown")
        => ApplyDamage(new DamageData(type, amount, sourceName));

    public void ApplyDamage(DamageData damageData)
    {
        if (!Multiplayer.IsServer() || _isDead) return;

        var actualDamage = CalculateDamageAmount(damageData);
        if (actualDamage <= 0) return;

        switch (damageData.Type)
        {
            case DamageType.Brute:
                _currentBruteDamage = Mathf.Min(_currentBruteDamage + actualDamage, MaxBruteDamage);
                break;
            case DamageType.Burn:
                _currentBurnDamage = Mathf.Min(_currentBurnDamage + actualDamage, MaxBurnDamage);
                break;
            case DamageType.Toxin:
                _currentToxinDamage = Mathf.Min(_currentToxinDamage + actualDamage, MaxToxinDamage);
                break;
            case DamageType.Oxygen:
                _currentOxygenDamage = Mathf.Min(_currentOxygenDamage + actualDamage, MaxOxygenDamage);
                break;
            default:
                // Clone/Brain/HalLoss/Special all hit overall health directly
                // for now - matching the old prototype's behavior.
                _currentHealth = Mathf.Max(0, _currentHealth - actualDamage);
                break;
        }

        UpdateHealthFromDamage();
        _timeSinceLastDamage = 0f;
        _isRegenerating = false;

        EmitSignal(SignalName.DamageTaken, (int)damageData.Type, damageData.Amount, damageData.SourceName, _currentHealth);
    }

    public void ApplyHealing(float amount)
    {
        if (!Multiplayer.IsServer() || _isDead) return;

        // Healing reduces typed damage evenly rather than raw health - health
        // is derived from damage totals, so healing "raw" health alone would
        // be undone by the next recompute.
        var perType = amount / 4f;
        _currentBruteDamage = Mathf.Max(0, _currentBruteDamage - perType);
        _currentBurnDamage = Mathf.Max(0, _currentBurnDamage - perType);
        _currentToxinDamage = Mathf.Max(0, _currentToxinDamage - perType);
        _currentOxygenDamage = Mathf.Max(0, _currentOxygenDamage - perType);
        UpdateHealthFromDamage();
    }

    private float CalculateDamageAmount(DamageData damageData)
    {
        var resistance = damageData.Type switch
        {
            DamageType.Brute => BruteResistance,
            DamageType.Burn => BurnResistance,
            DamageType.Toxin => ToxinResistance,
            DamageType.Oxygen => OxygenResistance,
            _ => 0f,
        };
        return Math.Max(0, damageData.Amount * (1.0f - resistance));
    }

    private void UpdateHealthFromDamage()
    {
        var totalDamage = (_currentBruteDamage / MaxBruteDamage +
                           _currentBurnDamage / MaxBurnDamage +
                           _currentToxinDamage / MaxToxinDamage +
                           _currentOxygenDamage / MaxOxygenDamage) / 4.0f;

        var oldHealth = _currentHealth;
        _currentHealth = Mathf.Max(0, MaxHealth * (1.0f - totalDamage));

        var criticalThreshold = MaxHealth * CriticalHealthFraction;
        if (_currentHealth <= 0 && oldHealth > 0)
        {
            _isDead = true;
            EmitSignal(SignalName.Death);
            _mob?.Destroy(); // drives the shared Atom Destroyed -> Mob.Died flow
        }
        else if (_currentHealth <= criticalThreshold && oldHealth > criticalThreshold)
        {
            EmitSignal(SignalName.CriticalHealth);
        }

        if (_currentHealth <= criticalThreshold)
        {
            _wasCritical = true;
        }
        else if (_wasCritical)
        {
            _wasCritical = false;
            EmitSignal(SignalName.CriticalRecovered);
        }

        EmitSignal(SignalName.HealthChanged, _currentHealth, MaxHealth);
    }

    private void UpdatePainLevel()
    {
        var newPainLevel = CalculatePainLevel(GetPainPercentage());
        if (newPainLevel == _currentPainLevel) return;

        var oldLevel = _currentPainLevel;
        _currentPainLevel = newPainLevel;
        EmitSignal(SignalName.PainLevelChanged, (int)newPainLevel, (int)oldLevel);
    }

    private float GetPainPercentage()
    {
        var totalPain = (_currentBruteDamage / MaxBruteDamage * BrutePainMultiplier +
                         _currentBurnDamage / MaxBurnDamage * BurnPainMultiplier +
                         _currentToxinDamage / MaxToxinDamage * ToxinPainMultiplier +
                         _currentOxygenDamage / MaxOxygenDamage * OxygenPainMultiplier) / 4.0f;
        return Math.Max(0, totalPain - _currentPainReduction / 100.0f) * 100.0f;
    }

    private PainLevel CalculatePainLevel(float painPercentage)
    {
        if (painPercentage >= PainThresholdHorrible) return PainLevel.Horrible;
        if (painPercentage >= PainThresholdSevere) return PainLevel.Severe;
        if (painPercentage >= PainThresholdDistressing) return PainLevel.Distressing;
        if (painPercentage >= PainThresholdModerate) return PainLevel.Moderate;
        if (painPercentage >= PainThresholdDiscomforting) return PainLevel.Discomforting;
        if (painPercentage >= PainThresholdMild) return PainLevel.Mild;
        return PainLevel.None;
    }

    private void HandleRegeneration(float delta)
    {
        if (_isDead || _timeSinceLastDamage < RegenDelay)
        {
            _isRegenerating = false;
            return;
        }

        if (!_isRegenerating && _currentHealth < MaxHealth) _isRegenerating = true;
        if (!_isRegenerating) return;

        var regenAmount = BaseRegenRate * delta;
        var hasRegen = false;

        if (_currentBruteDamage > 0) { _currentBruteDamage = Mathf.Max(0, _currentBruteDamage - regenAmount); hasRegen = true; }
        if (_currentBurnDamage > 0) { _currentBurnDamage = Mathf.Max(0, _currentBurnDamage - regenAmount); hasRegen = true; }
        if (_currentToxinDamage > 0) { _currentToxinDamage = Mathf.Max(0, _currentToxinDamage - regenAmount); hasRegen = true; }
        if (_currentOxygenDamage > 0) { _currentOxygenDamage = Mathf.Max(0, _currentOxygenDamage - regenAmount); hasRegen = true; }

        if (hasRegen) UpdateHealthFromDamage();
    }

    public void ApplyPainReduction(float amount)
    {
        _currentPainReduction = Math.Max(0, _currentPainReduction + amount);
        UpdatePainLevel();
    }

    public void ResetPainReduction()
    {
        _currentPainReduction = 0;
        UpdatePainLevel();
    }

    // ── Status effects ─────────────────────────────────────────────────────
    public void ApplyStatusEffect(StatusEffectType type, float durationSeconds)
    {
        if (!Multiplayer.IsServer()) return;

        var current = _statusTimers.GetValueOrDefault(type);
        if (current >= durationSeconds) return; // never shortens an existing effect

        _statusTimers[type] = durationSeconds;
        EmitSignal(SignalName.StatusMessage, $"You are {DescribeEffect(type)}!");
    }

    public bool HasStatusEffect(StatusEffectType type) => _statusTimers.GetValueOrDefault(type) > 0;

    // Convenience wrappers preserved from the old prototype's public API.
    public void Stun(float seconds) => ApplyStatusEffect(StatusEffectType.Stun, seconds);
    public void KnockDown(float seconds) => ApplyStatusEffect(StatusEffectType.KnockDown, seconds);
    public void KnockOut(float seconds) => ApplyStatusEffect(StatusEffectType.KnockOut, seconds);
    public void Daze(float seconds) => ApplyStatusEffect(StatusEffectType.Daze, seconds);
    public void Slow(float seconds) => ApplyStatusEffect(StatusEffectType.Slow, seconds);
    public void Superslow(float seconds) => ApplyStatusEffect(StatusEffectType.Superslow, seconds);
    public void Root(float seconds) => ApplyStatusEffect(StatusEffectType.Root, seconds);
    public void Sleep(float seconds) => ApplyStatusEffect(StatusEffectType.Sleeping, seconds);

    private static string DescribeEffect(StatusEffectType type) => type switch
    {
        StatusEffectType.Stun => "stunned",
        StatusEffectType.KnockDown => "knocked down",
        StatusEffectType.KnockOut => "knocked out",
        StatusEffectType.Daze => "dazed",
        StatusEffectType.Slow => "slowed",
        StatusEffectType.Superslow => "barely able to move",
        StatusEffectType.Root => "rooted",
        StatusEffectType.Sleeping => "falling asleep",
        StatusEffectType.EyeBlur => "seeing blurry",
        StatusEffectType.EyeBlind => "blinded",
        StatusEffectType.EarDeafness => "deafened",
        StatusEffectType.Stutter => "stuttering",
        StatusEffectType.Drowsy => "drowsy",
        _ => type.ToString().ToLowerInvariant(),
    };

    private void UpdateStatusTimers(float delta)
    {
        if (_statusTimers.Count == 0) return;

        // Snapshot keys - can't mutate while iterating.
        foreach (var type in new List<StatusEffectType>(_statusTimers.Keys))
        {
            var remaining = _statusTimers[type] - delta;
            if (remaining <= 0) _statusTimers.Remove(type);
            else _statusTimers[type] = remaining;
        }
    }

    private void ApplyStatusEffects()
    {
        if (_movement == null) return;

        var speedMultiplier = 1.0f;

        if (HasStatusEffect(StatusEffectType.Root)) speedMultiplier = 0f;
        if (HasStatusEffect(StatusEffectType.KnockDown)) speedMultiplier = 0f;
        if (HasStatusEffect(StatusEffectType.KnockOut)) speedMultiplier = 0f;
        if (HasStatusEffect(StatusEffectType.Stun)) speedMultiplier = 0f;
        if (HasStatusEffect(StatusEffectType.Sleeping)) speedMultiplier = 0f;
        if (HasStatusEffect(StatusEffectType.Daze)) speedMultiplier = Mathf.Min(speedMultiplier, 0.5f);
        if (HasStatusEffect(StatusEffectType.Slow)) speedMultiplier = Mathf.Min(speedMultiplier, 0.5f);
        if (HasStatusEffect(StatusEffectType.Superslow)) speedMultiplier = Mathf.Min(speedMultiplier, 0.25f);

        // Pain stacks multiplicatively on top of status effects.
        speedMultiplier *= _currentPainLevel switch
        {
            PainLevel.Mild => PainSpeedMild,
            PainLevel.Discomforting => PainSpeedDiscomforting,
            PainLevel.Moderate => PainSpeedModerate,
            PainLevel.Distressing => PainSpeedDistressing,
            PainLevel.Severe or PainLevel.Horrible => PainSpeedSevere,
            _ => 1.0f,
        };

        _movement.SpeedMultiplier = speedMultiplier;
    }

    // ── Queries ────────────────────────────────────────────────────────────
    public float CurrentHealth => _currentHealth;
    public float GetHealthPercentage() => _currentHealth / MaxHealth * 100.0f;
    public PainLevel GetCurrentPainLevel() => _currentPainLevel;
    public bool IsCriticalHealth() => _currentHealth <= MaxHealth * CriticalHealthFraction;
    public bool IsDead() => _isDead;

    public float GetDamage(DamageType type) => type switch
    {
        DamageType.Brute => _currentBruteDamage,
        DamageType.Burn => _currentBurnDamage,
        DamageType.Toxin => _currentToxinDamage,
        DamageType.Oxygen => _currentOxygenDamage,
        _ => 0f,
    };
}
