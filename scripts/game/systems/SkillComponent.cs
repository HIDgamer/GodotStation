using Godot;
using System;
using System.Collections.Generic;

public enum SkillType
{
    // Medical Skills.
    Medical = 0,
    Surgery = 1,
    
    // Science Skills.
    Research = 2,
    
    // Engineering skills.
    Engineer = 3,
    Construction = 4,
    
    // Combat Skills.
    CQC = 5,
    SpecWeapons = 6,
    
    // Specialized skills.
    Powerloader = 7,
    Intel = 8,
    Police = 9,
    JTAC = 10,
    Vehicle = 11,
    
    // Support Skills.
    FiremanCarry = 12,
    
    // Maximum skill count.
    MaxSkills = 13
}

public enum SkillLevel
{
    None = 0,
    Novice = 1,
    Trained = 2,
    Skilled = 3,
    Expert = 4,
    Master = 5
}

public partial class SkillComponent : Node
{
    private Mob _owner;
    private Dictionary<SkillType, int> _skills = new();
    private Dictionary<SkillType, string> _skillNames = new();
    private Dictionary<SkillType, string> _skillDescriptions = new();
    
    [Signal] public delegate void SkillChangedEventHandler(int skill, int level);

    public override void _Ready()
    {
        _owner = GetParent<Mob>();
        InitializeSkills();
    }

    private void InitializeSkills()
    {
        // Initialize all skills to level 0.
        foreach (SkillType skill in Enum.GetValues(typeof(SkillType)))
        {
            if (skill != SkillType.MaxSkills)
            {
                _skills[skill] = 0;
                SetSkillNameAndDescription(skill);
            }
        }
    }

    private void SetSkillNameAndDescription(SkillType skill)
    {
        switch (skill)
        {
            case SkillType.Medical:
                _skillNames[skill] = "Medical";
                _skillDescriptions[skill] = "Knowledge of medical procedures and first aid.";
                break;
            case SkillType.Surgery:
                _skillNames[skill] = "Surgery";
                _skillDescriptions[skill] = "Advanced medical knowledge for surgical procedures.";
                break;
            case SkillType.Research:
                _skillNames[skill] = "Research";
                _skillDescriptions[skill] = "Understanding of scientific research and laboratory work.";
                break;
            case SkillType.Engineer:
                _skillNames[skill] = "Engineering";
                _skillDescriptions[skill] = "Knowledge of machinery repair and maintenance.";
                break;
            case SkillType.Construction:
                _skillNames[skill] = "Construction";
                _skillDescriptions[skill] = "Ability to construct and repair fortifications.";
                break;
            case SkillType.CQC:
                _skillNames[skill] = "CQC";
                _skillDescriptions[skill] = "Close Quarters Combat proficiency.";
                break;
            case SkillType.SpecWeapons:
                _skillNames[skill] = "Specialist Weapons";
                _skillDescriptions[skill] = "Training with specialized weaponry.";
                break;
            case SkillType.Powerloader:
                _skillNames[skill] = "Powerloader";
                _skillDescriptions[skill] = "Ability to operate powerloader machinery.";
                break;
            case SkillType.Intel:
                _skillNames[skill] = "Intelligence";
                _skillDescriptions[skill] = "Ability to quickly process intelligence documents.";
                break;
            case SkillType.Police:
                _skillNames[skill] = "Police";
                _skillDescriptions[skill] = "Training in security equipment usage.";
                break;
            case SkillType.JTAC:
                _skillNames[skill] = "JTAC";
                _skillDescriptions[skill] = "Joint Terminal Attack Controller training.";
                break;
            case SkillType.Vehicle:
                _skillNames[skill] = "Vehicle Operation";
                _skillDescriptions[skill] = "Training in vehicle operation and maintenance.";
                break;
            case SkillType.FiremanCarry:
                _skillNames[skill] = "Fireman Carry";
                _skillDescriptions[skill] = "Ability to carry incapacitated personnel.";
                break;
        }
    }

    public void IncrementSkill(SkillType skill, int increment = 1, int cap = 5)
    {
        if (!_skills.ContainsKey(skill)) return;
        
        int newLevel = Math.Min(_skills[skill] + increment, cap);
        if (newLevel != _skills[skill])
        {
            _skills[skill] = newLevel;
            EmitSignal(SignalName.SkillChanged, (int)skill, newLevel);
            
            if (Multiplayer.IsServer())
                Rpc(MethodName.SyncSkill, (int)skill, newLevel);
        }
    }

    public void DecrementSkill(SkillType skill, int decrement = 1)
    {
        if (!_skills.ContainsKey(skill)) return;
        
        int newLevel = Math.Max(0, _skills[skill] - decrement);
        if (newLevel != _skills[skill])
        {
            _skills[skill] = newLevel;
            EmitSignal(SignalName.SkillChanged, (int)skill, newLevel);
            
            if (Multiplayer.IsServer())
                Rpc(MethodName.SyncSkill, (int)skill, newLevel);
        }
    }

    public int GetSkillLevel(SkillType skill)
    {
        return _skills.ContainsKey(skill) ? _skills[skill] : 0;
    }

    public SkillLevel GetSkillLevelEnum(SkillType skill)
    {
        int level = GetSkillLevel(skill);
        return (SkillLevel)Math.Min(level, 5);
    }

    public string GetSkillName(SkillType skill)
    {
        return _skillNames.ContainsKey(skill) ? _skillNames[skill] : skill.ToString();
    }

    public string GetSkillDescription(SkillType skill)
    {
        return _skillDescriptions.ContainsKey(skill) ? _skillDescriptions[skill] : "";
    }

    public Dictionary<SkillType, int> GetAllSkills()
    {
        return new Dictionary<SkillType, int>(_skills);
    }

    public bool HasSkill(SkillType skill, int minimumLevel = 1)
    {
        return GetSkillLevel(skill) >= minimumLevel;
    }

    // Skill-based checks for interactions.
    public bool CheckCQCAttack(SkillType attackerSkill, SkillType defenderSkill)
    {
        int attackerLevel = GetSkillLevel(attackerSkill);
        int defenderLevel = GetSkillLevel(defenderSkill);
        
        // Base chance based on skill difference.
        int skillDiff = attackerLevel - defenderLevel;
        float baseChance = 0.5f + (skillDiff * 0.1f);
        baseChance = Mathf.Clamp(baseChance, 0.1f, 0.9f);
        
        return GD.Randf() < baseChance;
    }

    public bool CheckDisarmSuccess(SkillType skill)
    {
        int skillLevel = GetSkillLevel(skill);
        float successChance = 0.25f + (skillLevel * 0.15f);
        successChance = Mathf.Clamp(successChance, 0.25f, 0.85f);
        
        return GD.Randf() < successChance;
    }

    public bool CheckStunSuccess(SkillType skill)
    {
        int skillLevel = GetSkillLevel(skill);
        float stunChance = 0.1f + (skillLevel * 0.1f);
        stunChance = Mathf.Clamp(stunChance, 0.1f, 0.5f);
        
        return GD.Randf() < stunChance;
    }

    public float GetCarrySpeedMultiplier(SkillType skill)
    {
        int skillLevel = GetSkillLevel(skill);
        return 1.0f - (skillLevel * 0.1f); // Higher skill = less speed penalty
    }

    public float GetCarryTimeMultiplier(SkillType skill)
    {
        int skillLevel = GetSkillLevel(skill);
        return 1.0f - (skillLevel * 0.1f); // Higher skill = faster carry
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void SyncSkill(int skillType, int level)
    {
        var skill = (SkillType)skillType;
        if (_skills.ContainsKey(skill))
        {
            _skills[skill] = level;
            EmitSignal(SignalName.SkillChanged, skillType, level);
        }
    }

    public void ApplyCharacterTraits(Godot.Collections.Dictionary characterData)
    {
        // Apply skill boosts based on character traits.
        if (characterData.ContainsKey("traits"))
        {
            var traits = (Godot.Collections.Array)characterData["traits"];
            
            foreach (var trait in traits)
            {
                ApplyTraitSkills(trait.ToString());
            }
        }
    }

    private void ApplyTraitSkills(string trait)
    {
        switch (trait)
        {
            case "First Aid Training":
                IncrementSkill(SkillType.Medical, 1, 1);
                break;
            case "Basic Lab Training":
                IncrementSkill(SkillType.Research, 1, 1);
                break;
            case "Basic Engineering Training":
                IncrementSkill(SkillType.Engineer, 1, 1);
                break;
            case "Basic Construction Training":
                IncrementSkill(SkillType.Construction, 1, 1);
                break;
            case "Field Technician Training":
                IncrementSkill(SkillType.Construction, 1, 1);
                IncrementSkill(SkillType.Engineer, 1, 1);
                break;
            case "JTAC Training":
                IncrementSkill(SkillType.JTAC, 1, 1);
                break;
            case "Powerloader Usage Training":
                IncrementSkill(SkillType.Powerloader, 1, 1);
                break;
            case "Intelligence training":
                IncrementSkill(SkillType.Intel, 1, 1);
                break;
            case "Police Training":
                IncrementSkill(SkillType.Police, 1, 1);
                break;
            case "Surgery Training":
                IncrementSkill(SkillType.Surgery, 1, 1);
                IncrementSkill(SkillType.Research, 3, 3);
                break;
        }
    }

    public void Cleanup() { }
}
