using Godot;
using GodotStation.Game.Mobs;
using GodotStation.Game.Mobs.Health;
using GodotStation.Game.Objects.Items;

namespace GodotStation.Game.Interaction;

// Intent-based melee resolution, ported from the old prototype's
// PlayerInteractionSystem handlers (its own original code). Server-only,
// stateless: the caller (PlayerMob's attack verb) owns adjacency checks,
// cooldowns, and networking; this just resolves what an intent DOES to a
// target. CQC modifiers read the real SkillComponent now that it's ported.
// Grab dispatches to the mob's own PlayerInteractionSystem, which owns the
// actual pull/grab-level/fireman-carry state machine this class doesn't.
public static class CombatResolver
{
    private const float UnarmedBaseDamage = 5.0f;
    private const float BaseHitChance = 0.6f;
    private const float BaseDisarmStunChance = 0.15f;
    private const float DisarmStunSeconds = 1.0f;

    // Returns a short feedback message for the attacker (empty = silent).
    public static string Resolve(Mob attacker, Mob target, Intent intent, Item? heldItem)
    {
        return intent switch
        {
            Intent.Help => ResolveHelp(target),
            Intent.Disarm => ResolveDisarm(attacker, target),
            Intent.Grab => ResolveGrab(attacker, target),
            Intent.Harm => ResolveHarm(attacker, target, heldItem),
            _ => "",
        };
    }

    private static string ResolveHelp(Mob target)
    {
        var targetState = target.GetMobComponent<MobStateSystem>();
        if (targetState != null && MobStateSystem.IsProneLike(targetState.State) && targetState.State != MobState.Dead)
        {
            targetState.HelpUp();
            return $"You help {target.AtomName} up.";
        }
        return $"You pat {target.AtomName} reassuringly.";
    }

    private static string ResolveDisarm(Mob attacker, Mob target)
    {
        // Old formula: 0.15 + ownerCQC*0.1 - targetCQC*0.05, clamped 5-75%.
        var ownerCqc = attacker.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var targetCqc = target.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var stunChance = Mathf.Clamp(BaseDisarmStunChance + ownerCqc * 0.1f - targetCqc * 0.05f, 0.05f, 0.75f);

        // Disarm always knocks the held item loose; the stun roll is the bonus.
        if (target is PlayerMob targetPlayer) targetPlayer.ForceDropActiveItem();

        if (GD.Randf() < stunChance)
        {
            target.GetMobComponent<MobStateSystem>()?.SetStunned(DisarmStunSeconds);
            return $"You shove {target.AtomName} to the ground!";
        }
        return $"You disarm {target.AtomName}.";
    }

    private static string ResolveGrab(Mob attacker, Mob target)
    {
        var interaction = attacker.GetMobComponent<PlayerInteractionSystem>();
        if (interaction == null) return $"You grab {target.AtomName}.";

        // The state machine reports its own feedback via StatusMessage -
        // nothing more to return here.
        interaction.HandleGrabIntent(target);
        return "";
    }

    private static string ResolveHarm(Mob attacker, Mob target, Item? heldItem)
    {
        // Old formula: 0.6 + ownerCQC*0.08 - targetCQC*0.04, clamped 30-95%.
        var ownerCqc = attacker.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var targetCqc = target.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var hitChance = Mathf.Clamp(BaseHitChance + ownerCqc * 0.08f - targetCqc * 0.04f, 0.3f, 0.95f);

        if (GD.Randf() >= hitChance)
        {
            return $"You swing at {target.AtomName} and miss!";
        }

        var damage = heldItem is MeleeWeapon weapon ? weapon.Damage : UnarmedBaseDamage + ownerCqc * 2.0f;
        target.GetMobComponent<HealthSystem>()?.ApplyDamage(DamageType.Brute, damage, attacker.AtomName);
        return $"You hit {target.AtomName}!";
    }
}
