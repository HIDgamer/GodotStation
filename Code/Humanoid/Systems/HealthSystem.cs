using Godot;
using System;

public enum DamageType { Brute, Burn, Toxin, Oxygen, Special }
public enum PainLevel { None, Mild, Discomforting, Moderate, Distressing, Severe, Horrible }

public struct DamageData
{
	public DamageType Type;
	public float Amount;
	public string SourceName;
	public object SourceObject;
	
	public DamageData(DamageType type, float amount, string sourceName = "Unknown", object sourceObject = null)
	{
		Type = type;
		Amount = amount;
		SourceName = sourceName;
		SourceObject = sourceObject;
	}
}

public struct HealingData
{
	public float Amount;
	public string SourceName;
	public object SourceObject;
	
	public HealingData(float amount, string sourceName = "Unknown", object sourceObject = null)
	{
		Amount = amount;
		SourceName = sourceName;
		SourceObject = sourceObject;
	}
}

public partial class HealthSystem : Node, IMobSystem
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
	
	[Export] public float BruteResistance = 0.0f;
	[Export] public float BurnResistance = 0.0f;
	[Export] public float ToxinResistance = 0.0f;
	[Export] public float OxygenResistance = 0.0f;
	
	[Export] public float PainSpeedVerySlow = 4.5f;
	[Export] public float PainSpeedSlow = 3.75f;
	[Export] public float PainSpeedHigh = 2.75f;
	[Export] public float PainSpeedMed = 1.5f;
	[Export] public float PainSpeedLow = 1.0f;
	
	private const float BrutePainMultiplier = 1.0f;
	private const float BurnPainMultiplier = 1.2f;
	private const float ToxinPainMultiplier = 1.5f;
	private const float OxygenPainMultiplier = 1.0f;
	
	private Mob _mob;
	private float _currentHealth;
	private float _currentBruteDamage;
	private float _currentBurnDamage;
	private float _currentToxinDamage;
	private float _currentOxygenDamage;
	private float _currentPainReduction;
	private float _timeSinceLastDamage;
	private PainLevel _currentPainLevel = PainLevel.None;
	private bool _isRegenerating;
	private bool _isProcessing;
	private bool _wasCritical;
	
	[Signal] public delegate void HealthChangedEventHandler(float currentHealth, float maxHealth);
	[Signal] public delegate void DamageTakenEventHandler(int damageType, float damageAmount, string sourceName, float remainingHealth);
	[Signal] public delegate void PainLevelChangedEventHandler(int newLevel, int oldLevel);
	[Signal] public delegate void CriticalHealthEventHandler();
	[Signal] public delegate void CriticalRecoveredEventHandler();
	[Signal] public delegate void DeathEventHandler();
	
	public override void _Ready()
	{
		base._Ready();
		InitializeHealth();
	}
	
	public void Init(Mob mob)
	{
		_mob = mob;
		InitializeHealth();
		_isProcessing = true;
	}
	
	public void Process(double delta)
	{
		if (!_isProcessing || _mob == null) return;
		
		_timeSinceLastDamage += (float)delta;
		UpdatePainLevel();
		HandleRegeneration((float)delta);
	}
	
	public void Cleanup() => _isProcessing = false;
	
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
		
		EmitSignal(SignalName.HealthChanged, _currentHealth, MaxHealth);
	}

	public void ApplyDamage(DamageData damageData)
	{
		if (!Multiplayer.IsServer()) return;
		
		float actualDamage = CalculateDamageAmount(damageData);
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
			case DamageType.Special:
				_currentHealth = Mathf.Max(0, _currentHealth - actualDamage);
				break;
		}
		
		UpdateHealthFromDamage();
		_timeSinceLastDamage = 0f;
		_isRegenerating = false;
		
		Rpc(MethodName.SyncDamageRpc, (int)damageData.Type, damageData.Amount, damageData.SourceName, _currentHealth);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncDamageRpc(int damageType, float damageAmount, string sourceName, float remainingHealth)
	{
		EmitSignal(SignalName.DamageTaken, damageType, damageAmount, sourceName, remainingHealth);
		ShowDamageFeedback(new DamageData((DamageType)damageType, damageAmount, sourceName));
	}
	
	public void ApplyDamage(DamageType type, float amount, string sourceName = "Unknown", object sourceObject = null)
	{
		ApplyDamage(new DamageData(type, amount, sourceName, sourceObject));
	}

	public void ApplyHealing(HealingData healingData)
	{
		if (!Multiplayer.IsServer()) return;
		
		_currentHealth = Math.Min(MaxHealth, _currentHealth + healingData.Amount);
		Rpc(MethodName.SyncHealthRpc, _currentHealth);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncHealthRpc(float currentHealth)
	{
		_currentHealth = currentHealth;
		EmitSignal(SignalName.HealthChanged, _currentHealth, MaxHealth);
	}

	public void ApplyHealing(float amount, string sourceName = "Unknown", object sourceObject = null)
	{
		ApplyHealing(new HealingData(amount, sourceName, sourceObject));
	}

	private float CalculateDamageAmount(DamageData damageData)
	{
		float resistance = damageData.Type switch
		{
			DamageType.Brute => BruteResistance,
			DamageType.Burn => BurnResistance,
			DamageType.Toxin => ToxinResistance,
			DamageType.Oxygen => OxygenResistance,
			_ => 0f
		};
		
		return Math.Max(0, damageData.Amount * (1.0f - resistance));
	}

	private void UpdateHealthFromDamage()
	{
		float totalDamage = (_currentBruteDamage / MaxBruteDamage) +
		                   (_currentBurnDamage / MaxBurnDamage) +
		                   (_currentToxinDamage / MaxToxinDamage) +
		                   (_currentOxygenDamage / MaxOxygenDamage);
		
		totalDamage /= 4.0f;
		float oldHealth = _currentHealth;
		_currentHealth = Mathf.Max(0, MaxHealth * (1.0f - totalDamage));
		
		float criticalThreshold = MaxHealth * 0.25f;
		if (_currentHealth <= 0 && oldHealth > 0)
			EmitSignal(SignalName.Death);
		else if (_currentHealth <= criticalThreshold && oldHealth > criticalThreshold)
			EmitSignal(SignalName.CriticalHealth);

		if (_currentHealth <= criticalThreshold)
		{
			_wasCritical = true;
		}
		else if (_wasCritical && _currentHealth > criticalThreshold)
		{
			_wasCritical = false;
			EmitSignal(SignalName.CriticalRecovered);
		}
		
		EmitSignal(SignalName.HealthChanged, _currentHealth, MaxHealth);
	}

	private void UpdatePainLevel()
	{
		float painPercentage = GetPainPercentage();
		PainLevel newPainLevel = CalculatePainLevel(painPercentage);
		
		if (newPainLevel != _currentPainLevel)
		{
			PainLevel oldLevel = _currentPainLevel;
			_currentPainLevel = newPainLevel;
			EmitSignal(SignalName.PainLevelChanged, (int)newPainLevel, (int)oldLevel);
			ApplyPainEffects();
		}
	}

	private float GetPainPercentage()
	{
		float brutePain = (_currentBruteDamage / MaxBruteDamage) * BrutePainMultiplier;
		float burnPain = (_currentBurnDamage / MaxBurnDamage) * BurnPainMultiplier;
		float toxinPain = (_currentToxinDamage / MaxToxinDamage) * ToxinPainMultiplier;
		float oxygenPain = (_currentOxygenDamage / MaxOxygenDamage) * OxygenPainMultiplier;
		
		float totalPain = (brutePain + burnPain + toxinPain + oxygenPain) / 4.0f;
		float effectivePain = Math.Max(0, totalPain - (_currentPainReduction / 100.0f));
		
		return effectivePain * 100.0f;
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

	private void ApplyPainEffects()
	{
		if (_mob == null) return;
		
		float speedMultiplier = _currentPainLevel switch
		{
			PainLevel.Mild => PainSpeedLow,
			PainLevel.Discomforting => PainSpeedMed,
			PainLevel.Moderate => PainSpeedHigh,
			PainLevel.Distressing => PainSpeedSlow,
			PainLevel.Severe or PainLevel.Horrible => PainSpeedVerySlow,
			_ => 1.0f
		};
		
		_mob.GetNodeOrNull<MovementController>("MovementController")?.SetSpeedMultiplier(speedMultiplier);
	}

	private void HandleRegeneration(float delta)
	{
		if (_timeSinceLastDamage < RegenDelay)
		{
			_isRegenerating = false;
			return;
		}
		
		if (!_isRegenerating && _currentHealth < MaxHealth)
			_isRegenerating = true;
		
		if (_isRegenerating)
		{
			float regenAmount = BaseRegenRate * delta;
			bool hasRegen = false;
			
			if (_currentBruteDamage > 0)
			{
				_currentBruteDamage = Mathf.Max(0, _currentBruteDamage - regenAmount);
				hasRegen = true;
			}
			if (_currentBurnDamage > 0)
			{
				_currentBurnDamage = Mathf.Max(0, _currentBurnDamage - regenAmount);
				hasRegen = true;
			}
			if (_currentToxinDamage > 0)
			{
				_currentToxinDamage = Mathf.Max(0, _currentToxinDamage - regenAmount);
				hasRegen = true;
			}
			if (_currentOxygenDamage > 0)
			{
				_currentOxygenDamage = Mathf.Max(0, _currentOxygenDamage - regenAmount);
				hasRegen = true;
			}
			
			if (hasRegen)
				UpdateHealthFromDamage();
		}
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

	private void ShowDamageFeedback(DamageData damageData)
	{
		_mob?.ShowChatBubble($"Took {damageData.Amount:F1} {damageData.Type} damage from {damageData.SourceName}");
	}

	public float GetHealthPercentage() => (_currentHealth / MaxHealth) * 100.0f;
	public float GetCurrentPainPercentage() => GetPainPercentage();
	public PainLevel GetCurrentPainLevel() => _currentPainLevel;
	
	public float GetDamage(DamageType type) => type switch
	{
		DamageType.Brute => _currentBruteDamage,
		DamageType.Burn => _currentBurnDamage,
		DamageType.Toxin => _currentToxinDamage,
		DamageType.Oxygen => _currentOxygenDamage,
		_ => 0f
	};
	
	public float GetMaxDamage(DamageType type) => type switch
	{
		DamageType.Brute => MaxBruteDamage,
		DamageType.Burn => MaxBurnDamage,
		DamageType.Toxin => MaxToxinDamage,
		DamageType.Oxygen => MaxOxygenDamage,
		_ => 0f
	};

	public bool IsCriticalHealth() => _currentHealth <= (MaxHealth * 0.25f);
	public bool IsDead() => _currentHealth <= 0;
	
	public override void _ExitTree()
	{
		_isProcessing = false;
		base._ExitTree();
	}
}
