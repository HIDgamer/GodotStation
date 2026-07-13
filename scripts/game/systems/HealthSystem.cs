using Godot;
using System;
using System.Collections.Generic;

public enum DamageType { Brute, Burn, Toxin, Oxygen, Clone, Brain, HalLoss, Special }
public enum PainLevel { None, Mild, Discomforting, Moderate, Distressing, Severe, Horrible }
public enum StatusEffectType 
{ 
	Stun, KnockDown, KnockOut, Daze, Slow, Superslow, Root, 
	Sleeping, EyeBlur, EyeBlind, EarDeafness, Stutter, Drowsy 
}

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

public struct StatusEffectData
{
	public StatusEffectType Type;
	public float Duration;
	public float StartTime;
	public bool Resistable;
	
	public StatusEffectData(StatusEffectType type, float duration, bool resistable = false)
	{
		Type = type;
		Duration = duration;
		StartTime = 0f;
		Resistable = resistable;
	}
}

public partial class HealthSystem : Node, IMobSystem, ISchedulable
{
	private Scheduler _scheduler;
	
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
	
	[Export] public float SchedulerUpdateInterval = 0.5f; // Update every 0.5 seconds
	[Export] public int SchedulerPriority = 8; // High priority for health system
	[Export] public bool SchedulerUpdateOnRegister = false;
	[Export] public bool EnableDebugLogging = false;
	
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
	
	private float _oxygenAccumulator = 0f;
	private float _bleedAccumulator = 0f;
	private float _toxinAccumulator = 0f;
	
	// Status Effects.
	private Dictionary<StatusEffectType, StatusEffectData> _statusEffects = new();
	private float _stunnedTime = 0f;
	private float _knockedDownTime = 0f;
	private float _knockedOutTime = 0f;
	private float _dazedTime = 0f;
	private float _slowTime = 0f;
	private float _superSlowTime = 0f;
	private float _rootTime = 0f;
	private float _sleepingTime = 0f;
	private float _eyeBlurTime = 0f;
	private float _eyeBlindTime = 0f;
	private float _earDeafnessTime = 0f;
	private float _stutterTime = 0f;
	private float _drowsyTime = 0f;
	
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
		
		_scheduler = GetNodeOrNull<Scheduler>("/root/Scheduler");
		
		if (_scheduler == null)
		{
			_scheduler = GetTree().GetFirstNodeInGroup("Scheduler") as Scheduler;
		}
		
		if (_scheduler != null)
		{
			_scheduler.Register(this);
			if (EnableDebugLogging)
				GD.Print("[HealthSystem] Registered with scheduler");
		}
		else
		{
			GD.PrintErr("[HealthSystem] No scheduler found in scene or autoloads!");
		}
	}
	
	public void Process(double delta)
	{
		if (!_isProcessing || _mob == null) return;
		
		_timeSinceLastDamage += (float)delta;
		
		UpdatePainLevel();
		
		HandleRegeneration((float)delta);
		
		UpdateStatusEffects((float)delta);
		ApplyStatusEffects();
	}
	
	public void ScheduledUpdate(float delta, WorldSnapshot snapshot)
	{
		if (!_isProcessing || _mob == null) return;
		
		_timeSinceLastDamage += delta;
		
		// Apply periodic damage based on accumulators.
		ApplyPeriodicDamage(delta);
		
		UpdatePainLevel();
		HandleRegeneration(delta);
		UpdateStatusEffects(delta);
		ApplyStatusEffects();
	}
	
	private void ApplyPeriodicDamage(float delta)
	{
		// Oxygen damage every 1.0 seconds.
		_oxygenAccumulator += delta;
		if (_oxygenAccumulator >= 1.0f && _currentOxygenDamage > 0)
		{
			float oxygenDamagePerSecond = 2.0f;
			float damageAmount = oxygenDamagePerSecond * _oxygenAccumulator;
			ApplyDamage(DamageType.Oxygen, damageAmount, "Asphyxiation");
			_oxygenAccumulator = 0f;
		}
		
		// Bleeding damage every 0.5 seconds.
		_bleedAccumulator += delta;
		if (_bleedAccumulator >= 0.5f && _currentBruteDamage > 0)
		{
			float brutePercentage = _currentBruteDamage / MaxBruteDamage;
			float bleedRate = 1.0f + (brutePercentage * 4.0f);
			float damageAmount = bleedRate * _bleedAccumulator;
			ApplyDamage(DamageType.Brute, damageAmount, "Bleeding");
			_bleedAccumulator = 0f;
		}
		
		// Toxin damage every 1.0 seconds.
		_toxinAccumulator += delta;
		if (_toxinAccumulator >= 1.0f && _currentToxinDamage > 0)
		{
			float toxinPercentage = _currentToxinDamage / MaxToxinDamage;
			float damagePerSecond = 0.5f + (toxinPercentage * 2.5f);
			float damageAmount = damagePerSecond * _toxinAccumulator;
			ApplyDamage(DamageType.Toxin, damageAmount, "Toxin");
			_toxinAccumulator = 0f;
		}
		
		// Natural bleeding stops after some time, then regeneration starts.
		if (_currentBruteDamage > 0 && _timeSinceLastDamage > RegenDelay)
		{
			float regenRate = 0.5f;
			_currentBruteDamage = Mathf.Max(0, _currentBruteDamage - (regenRate * delta));
			UpdateHealthFromDamage();
		}
	}
	
	public void Cleanup()
	{
		_isProcessing = false;
		
		// Unregister from scheduler.
		if (_scheduler != null)
		{
			_scheduler.Unregister(this);
		}
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
	
	public void SetPainLevel(float painLevel)
	{
		_currentPainLevel = (PainLevel)Mathf.Clamp(painLevel, 0, 6);
		EmitSignal(SignalName.PainLevelChanged, (int)_currentPainLevel, (int)_currentPainLevel);
	}
	
	public void SetPainLevel(PainLevel painLevel)
	{
		_currentPainLevel = painLevel;
		EmitSignal(SignalName.PainLevelChanged, (int)_currentPainLevel, (int)_currentPainLevel);
	}

	private void ShowDamageFeedback(DamageData damageData)
	{
		_mob?.ShowChatBubble($"Took {damageData.Amount:F1} {damageData.Type} damage from {damageData.SourceName}");
	}
	private void UpdateStatusEffects(float delta)
	{
		// Update status effect timers.
		if (_stunnedTime > 0) _stunnedTime -= delta;
		if (_knockedDownTime > 0) _knockedDownTime -= delta;
		if (_knockedOutTime > 0) _knockedOutTime -= delta;
		if (_dazedTime > 0) _dazedTime -= delta;
		if (_slowTime > 0) _slowTime -= delta;
		if (_superSlowTime > 0) _superSlowTime -= delta;
		if (_rootTime > 0) _rootTime -= delta;
		if (_sleepingTime > 0) _sleepingTime -= delta;
		if (_eyeBlurTime > 0) _eyeBlurTime -= delta;
		if (_eyeBlindTime > 0) _eyeBlindTime -= delta;
		if (_earDeafnessTime > 0) _earDeafnessTime -= delta;
		if (_stutterTime > 0) _stutterTime -= delta;
		if (_drowsyTime > 0) _drowsyTime -= delta;
	}

	private void ApplyStatusEffects()
	{
		if (_mob == null) return;
		
		var movementController = _mob.GetNodeOrNull<MovementController>("MovementController");
		if (movementController == null) return;

		// Apply movement effects.
		float speedMultiplier = 1.0f;
		bool canMove = true;
		bool canAct = true;

		if (_rootTime > 0)
		{
			canMove = false;
		}

		if (_knockedDownTime > 0)
		{
			canMove = false;
			speedMultiplier = 0.0f;
		}

		if (_knockedOutTime > 0)
		{
			canMove = false;
			canAct = false;
			speedMultiplier = 0.0f;
		}

		if (_stunnedTime > 0)
		{
			canAct = false;
			speedMultiplier = 0.0f;
		}

		if (_dazedTime > 0)
		{
			speedMultiplier = Mathf.Min(speedMultiplier, 0.5f);
		}

		// Slow.
		if (_slowTime > 0)
		{
			speedMultiplier = Mathf.Min(speedMultiplier, 0.5f);
		}

		// Superslow.
		if (_superSlowTime > 0)
		{
			speedMultiplier = Mathf.Min(speedMultiplier, 0.25f);
		}

		// Apply final speed multiplier.
		movementController.SetSpeedMultiplier(speedMultiplier);
	}

	// Status effect application methods.
	public void Stun(float amount, bool resistable = false)
	{
		if (_stunnedTime < amount)
		{
			_stunnedTime = amount;
			ShowStatusEffectMessage("stunned");
		}
	}

	public void KnockDown(float amount)
	{
		if (_knockedDownTime < amount)
		{
			_knockedDownTime = amount;
			ShowStatusEffectMessage("knocked down");
		}
	}

	public void KnockOut(float amount)
	{
		if (_knockedOutTime < amount)
		{
			_knockedOutTime = amount;
			ShowStatusEffectMessage("knocked out");
		}
	}

	public void Daze(float amount)
	{
		if (_dazedTime < amount)
		{
			_dazedTime = amount;
			ShowStatusEffectMessage("dazed");
		}
	}

	public void Slow(float amount)
	{
		if (_slowTime < amount)
		{
			_slowTime = amount;
			ShowStatusEffectMessage("slowed");
		}
	}

	public void Superslow(float amount)
	{
		if (_superSlowTime < amount)
		{
			_superSlowTime = amount;
			ShowStatusEffectMessage("super slowed");
		}
	}

	public void Root(float amount)
	{
		if (_rootTime < amount)
		{
			_rootTime = amount;
			ShowStatusEffectMessage("rooted");
		}
	}

	public void Sleeping(float amount)
	{
		if (_sleepingTime < amount)
		{
			_sleepingTime = amount;
			ShowStatusEffectMessage("sleeping");
		}
	}

	public void EyeBlur(float amount)
	{
		if (_eyeBlurTime < amount)
		{
			_eyeBlurTime = amount;
			ShowStatusEffectMessage("vision blurred");
		}
	}

	public void EyeBlind(float amount)
	{
		if (_eyeBlindTime < amount)
		{
			_eyeBlindTime = amount;
			ShowStatusEffectMessage("blinded");
		}
	}

	public void EarDeafness(float amount)
	{
		if (_earDeafnessTime < amount)
		{
			_earDeafnessTime = amount;
			ShowStatusEffectMessage("deafened");
		}
	}

	public void Stutter(float amount)
	{
		if (_stutterTime < amount)
		{
			_stutterTime = amount;
			ShowStatusEffectMessage("stuttering");
		}
	}

	public void Drowsy(float amount)
	{
		if (_drowsyTime < amount)
		{
			_drowsyTime = amount;
			ShowStatusEffectMessage("drowsy");
		}
	}

	private void ShowStatusEffectMessage(string effectName)
	{
		_mob?.ShowChatBubble($"You are {effectName}!");
	}
	
	private bool HasActiveStatusEffects()
	{
		return _stunnedTime > 0 || _knockedDownTime > 0 || _knockedOutTime > 0 ||
		       _dazedTime > 0 || _slowTime > 0 || _superSlowTime > 0 || _rootTime > 0 ||
		       _sleepingTime > 0 || _eyeBlurTime > 0 || _eyeBlindTime > 0 ||
		       _earDeafnessTime > 0 || _stutterTime > 0 || _drowsyTime > 0;
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
	
	public string SchedulerId => _mob?.GetPlayerName() + "_HealthSystem" ?? "Unknown_HealthSystem";
	public float UpdateInterval => SchedulerUpdateInterval;
	public int Priority => SchedulerPriority;
	public bool UpdateOnRegister => SchedulerUpdateOnRegister;
	public bool IsActive => _isProcessing && _mob != null;
	public bool NeedsProcessing => _isProcessing && _mob != null && (_currentBruteDamage > 0 || _currentBurnDamage > 0 || _currentToxinDamage > 0 || _currentOxygenDamage > 0 || _timeSinceLastDamage < RegenDelay || _currentPainLevel > PainLevel.None || HasActiveStatusEffects());
	
	public override void _ExitTree()
	{
		Cleanup();
		base._ExitTree();
	}
}
