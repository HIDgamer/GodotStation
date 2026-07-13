using System;
using System.Collections.Generic;
using Godot;

namespace GodotStation.Game.Mobs;

public enum SkillType
{
    Medical, Surgery, Research, Engineer, Construction, CQC, SpecWeapons,
    Powerloader, Intel, Police, JTAC, Vehicle, FiremanCarry,
}

public enum SkillLevel { None, Novice, Trained, Skilled, Expert, Master }

// Per-mob skill levels (CQC/medical/engineering/...), ported from the old
// prototype (its own original code) - zero dead-system dependencies, so
// this ports close to verbatim. Connection rebuild: no sync RPC (server-
// authoritative only, plain outward signal - matches HealthSystem/the
// rest of the reclaimed components; nothing client-side reads skills yet).
// ApplyCharacterTraits stays as a public entry point for the eventual
// character-creation/preferences system (Phase 6) - inert until that
// system calls it, same as it was in the old prototype before this port.
public partial class SkillComponent : Node, IMobComponent
{
    private const int MaxLevel = 5;

    private readonly Dictionary<SkillType, int> _skills = new();

    [Signal] public delegate void SkillChangedEventHandler(int skill, int level);

    public void Initialize(Mob mob)
    {
        foreach (SkillType skill in Enum.GetValues<SkillType>()) _skills[skill] = 0;
    }

    public void Cleanup() { }

    public void IncrementSkill(SkillType skill, int increment = 1, int cap = MaxLevel)
    {
        if (!Multiplayer.IsServer()) return;

        var newLevel = Math.Min(_skills[skill] + increment, cap);
        if (newLevel == _skills[skill]) return;

        _skills[skill] = newLevel;
        EmitSignal(SignalName.SkillChanged, (int)skill, newLevel);
    }

    public void DecrementSkill(SkillType skill, int decrement = 1)
    {
        if (!Multiplayer.IsServer()) return;

        var newLevel = Math.Max(0, _skills[skill] - decrement);
        if (newLevel == _skills[skill]) return;

        _skills[skill] = newLevel;
        EmitSignal(SignalName.SkillChanged, (int)skill, newLevel);
    }

    public int GetSkillLevel(SkillType skill) => _skills.GetValueOrDefault(skill);

    public SkillLevel GetSkillLevelEnum(SkillType skill) => (SkillLevel)Math.Min(GetSkillLevel(skill), MaxLevel);

    public bool HasSkill(SkillType skill, int minimumLevel = 1) => GetSkillLevel(skill) >= minimumLevel;

    // ── Skill-based checks used by combat/interaction (PlayerInteractionSystem) ──
    public bool CheckCQCAttack(SkillType attackerSkill, SkillType defenderSkill)
    {
        var skillDiff = GetSkillLevel(attackerSkill) - GetSkillLevel(defenderSkill);
        var chance = Mathf.Clamp(0.5f + skillDiff * 0.1f, 0.1f, 0.9f);
        return GD.Randf() < chance;
    }

    public bool CheckDisarmSuccess(SkillType skill)
    {
        var chance = Mathf.Clamp(0.25f + GetSkillLevel(skill) * 0.15f, 0.25f, 0.85f);
        return GD.Randf() < chance;
    }

    public bool CheckStunSuccess(SkillType skill)
    {
        var chance = Mathf.Clamp(0.1f + GetSkillLevel(skill) * 0.1f, 0.1f, 0.5f);
        return GD.Randf() < chance;
    }

    // Higher skill = less speed penalty / faster carry.
    public float GetCarrySpeedMultiplier(SkillType skill) => 1.0f - GetSkillLevel(skill) * 0.1f;
    public float GetCarryTimeMultiplier(SkillType skill) => 1.0f - GetSkillLevel(skill) * 0.1f;

    public void ApplyCharacterTraits(Godot.Collections.Dictionary characterData)
    {
        if (!characterData.ContainsKey("traits")) return;

        foreach (var trait in (Godot.Collections.Array)characterData["traits"])
        {
            ApplyTraitSkills(trait.ToString());
        }
    }

    private void ApplyTraitSkills(string trait)
    {
        switch (trait)
        {
            case "First Aid Training": IncrementSkill(SkillType.Medical, 1, 1); break;
            case "Basic Lab Training": IncrementSkill(SkillType.Research, 1, 1); break;
            case "Basic Engineering Training": IncrementSkill(SkillType.Engineer, 1, 1); break;
            case "Basic Construction Training": IncrementSkill(SkillType.Construction, 1, 1); break;
            case "Field Technician Training":
                IncrementSkill(SkillType.Construction, 1, 1);
                IncrementSkill(SkillType.Engineer, 1, 1);
                break;
            case "JTAC Training": IncrementSkill(SkillType.JTAC, 1, 1); break;
            case "Powerloader Usage Training": IncrementSkill(SkillType.Powerloader, 1, 1); break;
            case "Intelligence training": IncrementSkill(SkillType.Intel, 1, 1); break;
            case "Police Training": IncrementSkill(SkillType.Police, 1, 1); break;
            case "Surgery Training":
                IncrementSkill(SkillType.Surgery, 1, 1);
                IncrementSkill(SkillType.Research, 3, 3);
                break;
        }
    }
}
