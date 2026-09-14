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
//
// Harm and Disarm were audited against the real DM source (2026-09-14,
// human_attackhand.dm's attack_hand() INTENT_HARM/INTENT_DISARM branches) -
// see each method's own comment for what changed and why.
public static class CombatResolver
{
    private const float UnarmedBaseDamage = 5.0f;
    private const int DisarmStunThreshold = 25;
    private const int DisarmDropThreshold = 60;
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

    // Real DM formula: rand(1,100) - 5*attackerCQC + 5*defenderCQC against
    // two thresholds, not a single stun-chance roll - a disarm attempt can
    // whiff entirely (the old prototype this was ported from always dropped
    // the target's item and only rolled for the stun bonus, which didn't
    // match). Middle tier breaks an active pull instead of dropping the
    // item, if the target has one - also real DM behavior.
    private static string ResolveDisarm(Mob attacker, Mob target)
    {
        var ownerCqc = attacker.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var targetCqc = target.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var roll = (int)(GD.Randf() * 100) + 1 - 5 * ownerCqc + 5 * targetCqc;

        if (roll <= DisarmStunThreshold)
        {
            target.GetMobComponent<MobStateSystem>()?.SetStunned(DisarmStunSeconds);
            return $"You shove {target.AtomName} to the ground!";
        }

        if (roll <= DisarmDropThreshold)
        {
            var targetInteraction = target.GetMobComponent<PlayerInteractionSystem>();
            if (targetInteraction != null && targetInteraction.IsPulling())
            {
                targetInteraction.StopPull();
                return $"You break {target.AtomName}'s grip on what they were pulling!";
            }

            if (target is PlayerMob targetPlayer) targetPlayer.ForceDropActiveItem();
            return $"You disarm {target.AtomName}.";
        }

        return $"You attempt to disarm {target.AtomName}, but fail.";
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

    // Real DM harm intent has no to-hit roll at all - it's a guaranteed hit
    // (only which limb gets struck is randomized, not modeled here yet);
    // CQC skill adds bonus damage, it never gates whether the attack lands.
    // The old prototype this was ported from added a miss-chance roll that
    // doesn't exist in DM - removed.
    private static string ResolveHarm(Mob attacker, Mob target, Item? heldItem)
    {
        var ownerCqc = attacker.GetMobComponent<SkillComponent>()?.GetSkillLevel(SkillType.CQC) ?? 0;
        var damage = heldItem is MeleeWeapon weapon ? weapon.Damage : UnarmedBaseDamage + ownerCqc * 2.0f;
        target.GetMobComponent<HealthSystem>()?.ApplyDamage(DamageType.Brute, damage, attacker.AtomName);
        return $"You hit {target.AtomName}!";
    }
}
