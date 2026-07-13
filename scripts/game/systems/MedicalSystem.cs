using Godot;
using System;

public enum MedicalProcedureType { BasicHealing, AdvancedHealing, LimbTreatment, OrganTreatment, Surgery }

public partial class MedicalSystem : Node, IMobSystem, ISchedulable
{
	[Export] public float BasicHealingRate = 10.0f;
	[Export] public float AdvancedHealingRate = 25.0f;
	[Export] public float LimbTreatmentRate = 15.0f;
	[Export] public float OrganTreatmentRate = 20.0f;
	[Export] public float SurgerySuccessRate = 0.8f;
	[Export] public float SurgeryFailureRate = 0.1f;
	
	[Export] public float SchedulerUpdateInterval = 0.5f; // Update every 0.5 seconds
	[Export] public int SchedulerPriority = 6; // Medium-High priority
	[Export] public bool SchedulerUpdateOnRegister = false;
	[Export] public bool EnableDebugLogging = false;
	
	private Mob _mob;
	private bool _isProcessing;
	private float _surgeryTimer = 0f;
	private bool _isPerformingSurgery = false;
	private LimbType _targetLimb = LimbType.Body;
	private OrganType _targetOrgan = OrganType.Heart;
	private Scheduler _scheduler;
	
	[Signal] public delegate void MedicalProcedureStartedEventHandler(int procedureType, string target);
	[Signal] public delegate void MedicalProcedureCompletedEventHandler(int procedureType, bool success);
	[Signal] public delegate void MedicalProcedureFailedEventHandler(int procedureType, string reason);
	
	public override void _Ready()
	{
		base._Ready();
		InitializeMedicalSystem();
		
		_scheduler = GetNodeOrNull<Scheduler>("/root/Scheduler");
		
		if (_scheduler == null)
		{
			_scheduler = GetTree().GetFirstNodeInGroup("Scheduler") as Scheduler;
		}
		
		if (_scheduler != null)
		{
			_scheduler.Register(this);
			if (EnableDebugLogging)
				GD.Print("[MedicalSystem] Registered with scheduler");
		}
		else
		{
			GD.PrintErr("[MedicalSystem] No scheduler found in scene or autoloads!");
		}
	}
	
	public void Init(Mob mob)
	{
		_mob = mob;
		InitializeMedicalSystem();
		_isProcessing = true;
	}
	
	public void Process(double delta)
	{
		if (!_isProcessing || _mob == null) return;
		
		if (_isPerformingSurgery)
		{
			UpdateSurgery((float)delta);
		}
	}
	
	public void ScheduledUpdate(float delta, WorldSnapshot snapshot)
	{
		if (!_isProcessing || _mob == null) return;
		
		if (_isPerformingSurgery)
		{
			UpdateSurgery(delta);
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
	
	private void InitializeMedicalSystem()
	{
		_isPerformingSurgery = false;
		_surgeryTimer = 0f;
	}
	
	public void StartMedicalProcedure(MedicalProcedureType procedureType, LimbType limb = LimbType.Body, OrganType organ = OrganType.Heart)
	{
		if (!Multiplayer.IsServer()) return;
		
		_targetLimb = limb;
		_targetOrgan = organ;
		
		switch (procedureType)
		{
			case MedicalProcedureType.BasicHealing:
				PerformBasicHealing();
				break;
			case MedicalProcedureType.AdvancedHealing:
				PerformAdvancedHealing();
				break;
			case MedicalProcedureType.LimbTreatment:
				PerformLimbTreatment();
				break;
			case MedicalProcedureType.OrganTreatment:
				PerformOrganTreatment();
				break;
			case MedicalProcedureType.Surgery:
				StartSurgery();
				break;
		}
	}
	
	private void PerformBasicHealing()
	{
		var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (healthSystem != null)
		{
			healthSystem.ApplyHealing(BasicHealingRate);
			EmitSignal(SignalName.MedicalProcedureCompleted, (int)MedicalProcedureType.BasicHealing, true);
		}
	}
	
	private void PerformAdvancedHealing()
	{
		var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (healthSystem != null)
		{
			healthSystem.ApplyHealing(AdvancedHealingRate);
			healthSystem.ApplyPainReduction(2.0f);
			EmitSignal(SignalName.MedicalProcedureCompleted, (int)MedicalProcedureType.AdvancedHealing, true);
		}
	}
	
	private void PerformLimbTreatment()
	{
		var limbSystem = _mob.GetNodeOrNull<LimbSystem>("LimbSystem");
		if (limbSystem != null)
		{
			limbSystem.HealLimb(_targetLimb, DamageType.Brute, LimbTreatmentRate);
			limbSystem.HealLimb(_targetLimb, DamageType.Burn, LimbTreatmentRate);
			EmitSignal(SignalName.MedicalProcedureCompleted, (int)MedicalProcedureType.LimbTreatment, true);
		}
	}
	
	private void PerformOrganTreatment()
	{
		var limbSystem = _mob.GetNodeOrNull<LimbSystem>("LimbSystem");
		if (limbSystem != null)
		{
			limbSystem.HealOrgan(_targetOrgan, OrganTreatmentRate);
			EmitSignal(SignalName.MedicalProcedureCompleted, (int)MedicalProcedureType.OrganTreatment, true);
		}
	}
	
	private void StartSurgery()
	{
		_isPerformingSurgery = true;
		_surgeryTimer = 0f;
		EmitSignal(SignalName.MedicalProcedureStarted, (int)MedicalProcedureType.Surgery, _targetOrgan.ToString());
	}
	
	private void UpdateSurgery(float delta)
	{
		_surgeryTimer += delta;
		
		if (_surgeryTimer >= 5.0f) // Surgery takes 5 seconds
		{
			CompleteSurgery();
		}
	}
	
	private void CompleteSurgery()
	{
		var random = new RandomNumberGenerator();
		random.Randomize();
		
		float roll = random.Randf();
		
		if (roll < SurgerySuccessRate)
		{
			var limbSystem = _mob.GetNodeOrNull<LimbSystem>("LimbSystem");
			if (limbSystem != null)
			{
				limbSystem.HealOrgan(_targetOrgan, 50.0f);
				limbSystem.HealLimb(_targetLimb, DamageType.Brute, 30.0f);
				limbSystem.HealLimb(_targetLimb, DamageType.Burn, 30.0f);
			}
			
			var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
			if (healthSystem != null)
			{
				healthSystem.ApplyHealing(40.0f);
				healthSystem.ApplyPainReduction(3.0f);
			}
			
			EmitSignal(SignalName.MedicalProcedureCompleted, (int)MedicalProcedureType.Surgery, true);
			ShowMedicalMessage("Surgery successful!");
		}
		else if (roll < SurgerySuccessRate + SurgeryFailureRate)
		{
			var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
			if (healthSystem != null)
			{
				healthSystem.ApplyDamage(DamageType.Brute, 20.0f, "surgical complications", this);
			}
			
			EmitSignal(SignalName.MedicalProcedureFailed, (int)MedicalProcedureType.Surgery, "Surgical complications");
			ShowMedicalMessage("Surgery failed! You took damage from complications.");
		}
		else
		{
			var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
			if (healthSystem != null)
			{
				healthSystem.ApplyDamage(DamageType.Brute, 50.0f, "critical surgical failure", this);
				healthSystem.Stun(3.0f);
			}
			
			EmitSignal(SignalName.MedicalProcedureFailed, (int)MedicalProcedureType.Surgery, "Critical surgical failure");
			ShowMedicalMessage("Critical surgical failure! You are severely injured.");
		}
		
		_isPerformingSurgery = false;
		_surgeryTimer = 0f;
	}
	
	private void ShowMedicalMessage(string message)
	{
		_mob?.ShowChatBubble(message);
	}
	
	public bool IsPerformingSurgery() => _isPerformingSurgery;
	public float GetSurgeryProgress() => _isPerformingSurgery ? Mathf.Min(_surgeryTimer / 5.0f, 1.0f) : 0f;
	
	public string SchedulerId => "MedicalSystem_" + GetPath();
	public float UpdateInterval => SchedulerUpdateInterval;
	public int Priority => SchedulerPriority;
	public bool UpdateOnRegister => SchedulerUpdateOnRegister;
	public bool IsActive => IsInsideTree() && _isProcessing && _mob != null;
	public bool NeedsProcessing => _isProcessing && _mob != null && _isPerformingSurgery;
	
	public override void _ExitTree()
	{
		Cleanup();
		base._ExitTree();
	}
}
