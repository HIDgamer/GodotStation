using System.Collections.Generic;
using Godot;

namespace GodotStation.Game.Mobs.Health;

public enum LimbType { Head, Body, LeftArm, RightArm, LeftLeg, RightLeg, Groin }

public enum OrganType { Brain, Heart, Lungs, Stomach, Liver, Kidneys, Intestines }

public struct LimbDamage
{
    public float BruteDamage;
    public float BurnDamage;
    public float ToxinDamage;
    public float OxygenDamage;

    public readonly float Total => BruteDamage + BurnDamage + ToxinDamage + OxygenDamage;
}

public struct OrganDamage
{
    public float Damage;
    public bool IsDamaged;
}

// Per-limb/per-organ localized damage, ported from the old prototype.
// Same connection rebuild as HealthSystem: no sync RPCs (server-side only,
// signals outward), Scheduler dropped (slow regen rides _Process - it's a
// handful of dictionary entries), organ knock-on effects reach sibling
// components through Mob.GetMobComponent instead of node-path lookups.
public partial class LimbSystem : Node, IMobComponent
{
    [Export] public float MaxLimbDamage = 100f;
    [Export] public float MaxOrganDamage = 100f;
    [Export] public float LimbRegenRate = 0.5f;
    [Export] public float OrganRegenRate = 0.2f;

    [Signal] public delegate void LimbDamageChangedEventHandler(int limbType, float bruteDamage, float burnDamage, float toxinDamage, float oxygenDamage);
    [Signal] public delegate void OrganDamageChangedEventHandler(int organType, float damage, bool isDamaged);
    [Signal] public delegate void LimbStateChangedEventHandler(int limbType, string state);

    private Mob? _mob;
    private bool _isProcessing;
    private readonly Dictionary<LimbType, LimbDamage> _limbDamage = new();
    private readonly Dictionary<OrganType, OrganDamage> _organDamage = new();

    public void Initialize(Mob mob)
    {
        _mob = mob;
        InitializeLimbs();
        _isProcessing = true;
    }

    public void Cleanup() => _isProcessing = false;

    private void InitializeLimbs()
    {
        foreach (LimbType limb in System.Enum.GetValues<LimbType>()) _limbDamage[limb] = default;
        foreach (OrganType organ in System.Enum.GetValues<OrganType>()) _organDamage[organ] = default;
    }

    public override void _Process(double delta)
    {
        if (!_isProcessing || _mob == null || !Multiplayer.IsServer()) return;
        UpdateRegeneration((float)delta);
    }

    private void UpdateRegeneration(float delta)
    {
        foreach (var limb in new List<LimbType>(_limbDamage.Keys))
        {
            var damage = _limbDamage[limb];
            if (damage.Total <= 0) continue;

            var regen = LimbRegenRate * delta;
            damage.BruteDamage = Mathf.Max(0, damage.BruteDamage - regen);
            damage.BurnDamage = Mathf.Max(0, damage.BurnDamage - regen);
            damage.ToxinDamage = Mathf.Max(0, damage.ToxinDamage - regen);
            damage.OxygenDamage = Mathf.Max(0, damage.OxygenDamage - regen);
            _limbDamage[limb] = damage;
            EmitLimbChanged(limb);
        }

        foreach (var organ in new List<OrganType>(_organDamage.Keys))
        {
            var damage = _organDamage[organ];
            if (damage.Damage <= 0) continue;

            damage.Damage = Mathf.Max(0, damage.Damage - OrganRegenRate * delta);
            if (damage.Damage <= 0) damage.IsDamaged = false;
            _organDamage[organ] = damage;
            EmitSignal(SignalName.OrganDamageChanged, (int)organ, damage.Damage, damage.IsDamaged);
        }
    }

    public void ApplyLimbDamage(LimbType limb, DamageType damageType, float amount)
    {
        if (!Multiplayer.IsServer()) return;

        var damage = _limbDamage[limb];
        switch (damageType)
        {
            case DamageType.Brute: damage.BruteDamage = Mathf.Min(damage.BruteDamage + amount, MaxLimbDamage); break;
            case DamageType.Burn: damage.BurnDamage = Mathf.Min(damage.BurnDamage + amount, MaxLimbDamage); break;
            case DamageType.Toxin: damage.ToxinDamage = Mathf.Min(damage.ToxinDamage + amount, MaxLimbDamage); break;
            case DamageType.Oxygen: damage.OxygenDamage = Mathf.Min(damage.OxygenDamage + amount, MaxLimbDamage); break;
        }
        _limbDamage[limb] = damage;

        EmitLimbChanged(limb);
        CheckLimbState(limb);
    }

    public void ApplyOrganDamage(OrganType organ, float amount)
    {
        if (!Multiplayer.IsServer()) return;

        var damage = _organDamage[organ];
        damage.Damage = Mathf.Min(damage.Damage + amount, MaxOrganDamage);
        damage.IsDamaged = true;
        _organDamage[organ] = damage;

        EmitSignal(SignalName.OrganDamageChanged, (int)organ, damage.Damage, damage.IsDamaged);
        CheckOrganEffects(organ);
    }

    public void HealLimb(LimbType limb, DamageType damageType, float amount)
        => ApplyLimbDamage(limb, damageType, -amount);

    public void HealOrgan(OrganType organ, float amount)
    {
        if (!Multiplayer.IsServer()) return;

        var damage = _organDamage[organ];
        damage.Damage = Mathf.Max(0, damage.Damage - amount);
        if (damage.Damage <= 0) damage.IsDamaged = false;
        _organDamage[organ] = damage;

        EmitSignal(SignalName.OrganDamageChanged, (int)organ, damage.Damage, damage.IsDamaged);
    }

    private void EmitLimbChanged(LimbType limb)
    {
        var d = _limbDamage[limb];
        EmitSignal(SignalName.LimbDamageChanged, (int)limb, d.BruteDamage, d.BurnDamage, d.ToxinDamage, d.OxygenDamage);
    }

    private void CheckLimbState(LimbType limb)
    {
        var total = _limbDamage[limb].Total;
        var state = total > MaxLimbDamage * 0.75f ? "critical" :
                    total > MaxLimbDamage * 0.5f ? "damaged" :
                    total > MaxLimbDamage * 0.25f ? "injured" : "healthy";
        EmitSignal(SignalName.LimbStateChanged, (int)limb, state);
    }

    // Organ damage bleeds into whole-body consequences.
    private void CheckOrganEffects(OrganType organ)
    {
        if (_mob == null) return;
        var damage = _organDamage[organ];
        var health = _mob.GetMobComponent<HealthSystem>();

        switch (organ)
        {
            case OrganType.Brain when damage.Damage > MaxOrganDamage * 0.5f:
                health?.ApplyDamage(DamageType.Brain, damage.Damage * 0.1f, "brain damage");
                break;
            case OrganType.Heart when damage.Damage > MaxOrganDamage * 0.3f:
                health?.Slow(2f);
                break;
            case OrganType.Lungs when damage.Damage > MaxOrganDamage * 0.3f:
                health?.ApplyDamage(DamageType.Oxygen, damage.Damage * 0.1f, "lung damage");
                break;
        }
    }

    public float GetLimbDamage(LimbType limb, DamageType damageType) => damageType switch
    {
        DamageType.Brute => _limbDamage[limb].BruteDamage,
        DamageType.Burn => _limbDamage[limb].BurnDamage,
        DamageType.Toxin => _limbDamage[limb].ToxinDamage,
        DamageType.Oxygen => _limbDamage[limb].OxygenDamage,
        _ => 0f,
    };

    public float GetOrganDamage(OrganType organ) => _organDamage[organ].Damage;
    public bool IsOrganDamaged(OrganType organ) => _organDamage[organ].IsDamaged;
}
