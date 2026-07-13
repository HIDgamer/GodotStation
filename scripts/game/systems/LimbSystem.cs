using Godot;
using System;
using System.Collections.Generic;

public enum LimbType { Head, Body, LeftArm, RightArm, LeftLeg, RightLeg, Groin }
public enum OrganType { Brain, Heart, Lungs, Stomach, Liver, Kidneys, Intestines }

public struct LimbDamage
{
	public float BruteDamage;
	public float BurnDamage;
	public float ToxinDamage;
	public float OxygenDamage;
	
	public LimbDamage(float brute = 0, float burn = 0, float toxin = 0, float oxygen = 0)
	{
		BruteDamage = brute;
		BurnDamage = burn;
		ToxinDamage = toxin;
		OxygenDamage = oxygen;
	}
}

public struct OrganDamage
{
	public float Damage;
	public bool IsDamaged;
	
	public OrganDamage(float damage = 0, bool isDamaged = false)
	{
		Damage = damage;
		IsDamaged = isDamaged;
	}
}

public partial class LimbSystem : Node, IMobSystem
{
	[Export] public float MaxLimbDamage = 100f;
	[Export] public float MaxOrganDamage = 100f;
	[Export] public float LimbRegenRate = 0.5f;
	[Export] public float OrganRegenRate = 0.2f;
	
	private Mob _mob;
	private Dictionary<LimbType, LimbDamage> _limbDamage = new();
	private Dictionary<OrganType, OrganDamage> _organDamage = new();
	private bool _isProcessing;
	
	[Signal] public delegate void LimbDamageChangedEventHandler(int limbType, float bruteDamage, float burnDamage, float toxinDamage, float oxygenDamage);
	[Signal] public delegate void OrganDamageChangedEventHandler(int organType, float damage, bool isDamaged);
	[Signal] public delegate void LimbStateChangedEventHandler(int limbType, string state);
	
	public override void _Ready()
	{
		base._Ready();
		InitializeLimbs();
	}
	
	public void Init(Mob mob)
	{
		_mob = mob;
		InitializeLimbs();
		_isProcessing = true;
	}
	
	public void Process(double delta)
	{
		if (!_isProcessing || _mob == null) return;
		
		UpdateLimbRegeneration((float)delta);
	}
	
	public void Cleanup() => _isProcessing = false;
	
	private void InitializeLimbs()
	{
		_limbDamage[LimbType.Head] = new LimbDamage();
		_limbDamage[LimbType.Body] = new LimbDamage();
		_limbDamage[LimbType.LeftArm] = new LimbDamage();
		_limbDamage[LimbType.RightArm] = new LimbDamage();
		_limbDamage[LimbType.LeftLeg] = new LimbDamage();
		_limbDamage[LimbType.RightLeg] = new LimbDamage();
		_limbDamage[LimbType.Groin] = new LimbDamage();
		
		_organDamage[OrganType.Brain] = new OrganDamage();
		_organDamage[OrganType.Heart] = new OrganDamage();
		_organDamage[OrganType.Lungs] = new OrganDamage();
		_organDamage[OrganType.Stomach] = new OrganDamage();
		_organDamage[OrganType.Liver] = new OrganDamage();
		_organDamage[OrganType.Kidneys] = new OrganDamage();
		_organDamage[OrganType.Intestines] = new OrganDamage();
	}
	
	private void UpdateLimbRegeneration(float delta)
	{
		bool updated = false;
		
		foreach (var limb in _limbDamage.Keys)
		{
			var damage = _limbDamage[limb];
			
			if (damage.BruteDamage > 0)
			{
				damage.BruteDamage = Mathf.Max(0, damage.BruteDamage - LimbRegenRate * delta);
				updated = true;
			}
			if (damage.BurnDamage > 0)
			{
				damage.BurnDamage = Mathf.Max(0, damage.BurnDamage - LimbRegenRate * delta);
				updated = true;
			}
			if (damage.ToxinDamage > 0)
			{
				damage.ToxinDamage = Mathf.Max(0, damage.ToxinDamage - LimbRegenRate * delta);
				updated = true;
			}
			if (damage.OxygenDamage > 0)
			{
				damage.OxygenDamage = Mathf.Max(0, damage.OxygenDamage - LimbRegenRate * delta);
				updated = true;
			}
			
			_limbDamage[limb] = damage;
		}
		
		foreach (var organ in _organDamage.Keys)
		{
			var damage = _organDamage[organ];
			
			if (damage.Damage > 0)
			{
				damage.Damage = Mathf.Max(0, damage.Damage - OrganRegenRate * delta);
				if (damage.Damage <= 0)
					damage.IsDamaged = false;
				updated = true;
			}
			
			_organDamage[organ] = damage;
		}
		
		if (updated)
		{
			EmitSignals();
		}
	}
	
	private void EmitSignals()
	{
		foreach (var limb in _limbDamage)
		{
			EmitSignal(SignalName.LimbDamageChanged, (int)limb.Key, 
				limb.Value.BruteDamage, limb.Value.BurnDamage, 
				limb.Value.ToxinDamage, limb.Value.OxygenDamage);
		}
		
		foreach (var organ in _organDamage)
		{
			EmitSignal(SignalName.OrganDamageChanged, (int)organ.Key, 
				organ.Value.Damage, organ.Value.IsDamaged);
		}
	}
	
	public void ApplyLimbDamage(LimbType limb, DamageType damageType, float amount)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (!_limbDamage.ContainsKey(limb)) return;
		
		var damage = _limbDamage[limb];
		
		switch (damageType)
		{
			case DamageType.Brute:
				damage.BruteDamage = Mathf.Min(damage.BruteDamage + amount, MaxLimbDamage);
				break;
			case DamageType.Burn:
				damage.BurnDamage = Mathf.Min(damage.BurnDamage + amount, MaxLimbDamage);
				break;
			case DamageType.Toxin:
				damage.ToxinDamage = Mathf.Min(damage.ToxinDamage + amount, MaxLimbDamage);
				break;
			case DamageType.Oxygen:
				damage.OxygenDamage = Mathf.Min(damage.OxygenDamage + amount, MaxLimbDamage);
				break;
		}
		
		_limbDamage[limb] = damage;
		EmitSignal(SignalName.LimbDamageChanged, (int)limb, 
			damage.BruteDamage, damage.BurnDamage, 
			damage.ToxinDamage, damage.OxygenDamage);
		
		Rpc(MethodName.SyncLimbDamageRpc, (int)limb, 
			damage.BruteDamage, damage.BurnDamage, 
			damage.ToxinDamage, damage.OxygenDamage);
		
		CheckLimbState(limb);
	}
	
	public void ApplyOrganDamage(OrganType organ, float amount)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (!_organDamage.ContainsKey(organ)) return;
		
		var damage = _organDamage[organ];
		damage.Damage = Mathf.Min(damage.Damage + amount, MaxOrganDamage);
		damage.IsDamaged = true;
		
		_organDamage[organ] = damage;
		EmitSignal(SignalName.OrganDamageChanged, (int)organ, damage.Damage, damage.IsDamaged);
		
		Rpc(MethodName.SyncOrganDamageRpc, (int)organ, damage.Damage, damage.IsDamaged);
		
		CheckOrganEffects(organ);
	}
	
	public void HealLimb(LimbType limb, DamageType damageType, float amount)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (!_limbDamage.ContainsKey(limb)) return;
		
		var damage = _limbDamage[limb];
		
		switch (damageType)
		{
			case DamageType.Brute:
				damage.BruteDamage = Mathf.Max(0, damage.BruteDamage - amount);
				break;
			case DamageType.Burn:
				damage.BurnDamage = Mathf.Max(0, damage.BurnDamage - amount);
				break;
			case DamageType.Toxin:
				damage.ToxinDamage = Mathf.Max(0, damage.ToxinDamage - amount);
				break;
			case DamageType.Oxygen:
				damage.OxygenDamage = Mathf.Max(0, damage.OxygenDamage - amount);
				break;
		}
		
		_limbDamage[limb] = damage;
		EmitSignal(SignalName.LimbDamageChanged, (int)limb, 
			damage.BruteDamage, damage.BurnDamage, 
			damage.ToxinDamage, damage.OxygenDamage);
		
		Rpc(MethodName.SyncLimbDamageRpc, (int)limb, 
			damage.BruteDamage, damage.BurnDamage, 
			damage.ToxinDamage, damage.OxygenDamage);
	}
	
	public void HealOrgan(OrganType organ, float amount)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (!_organDamage.ContainsKey(organ)) return;
		
		var damage = _organDamage[organ];
		damage.Damage = Mathf.Max(0, damage.Damage - amount);
		if (damage.Damage <= 0)
			damage.IsDamaged = false;
		
		_organDamage[organ] = damage;
		EmitSignal(SignalName.OrganDamageChanged, (int)organ, damage.Damage, damage.IsDamaged);
		
		Rpc(MethodName.SyncOrganDamageRpc, (int)organ, damage.Damage, damage.IsDamaged);
	}
	
	private void CheckLimbState(LimbType limb)
	{
		if (!_limbDamage.ContainsKey(limb)) return;
		
		var damage = _limbDamage[limb];
		float totalDamage = damage.BruteDamage + damage.BurnDamage + damage.ToxinDamage + damage.OxygenDamage;
		
		string state = totalDamage > MaxLimbDamage * 0.75f ? "critical" :
					   totalDamage > MaxLimbDamage * 0.5f ? "damaged" :
					   totalDamage > MaxLimbDamage * 0.25f ? "injured" : "healthy";
		
		EmitSignal(SignalName.LimbStateChanged, (int)limb, state);
	}
	
	private void CheckOrganEffects(OrganType organ)
	{
		if (!_organDamage.ContainsKey(organ)) return;
		
		var damage = _organDamage[organ];
		
		switch (organ)
		{
			case OrganType.Brain:
				if (damage.Damage > MaxOrganDamage * 0.5f)
				{
					var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
					healthSystem?.ApplyDamage(DamageType.Brain, damage.Damage * 0.1f, "brain damage", this);
				}
				break;
			case OrganType.Heart:
				if (damage.Damage > MaxOrganDamage * 0.3f)
				{
					var movementController = _mob.GetNodeOrNull<MovementController>("MovementController");
					movementController?.SetSpeedMultiplier(0.75f);
				}
				break;
			case OrganType.Lungs:
				if (damage.Damage > MaxOrganDamage * 0.3f)
				{
					var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
					healthSystem?.ApplyDamage(DamageType.Oxygen, damage.Damage * 0.1f, "lung damage", this);
				}
				break;
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLimbDamageRpc(int limbType, float bruteDamage, float burnDamage, float toxinDamage, float oxygenDamage)
	{
		var limb = (LimbType)limbType;
		if (!_limbDamage.ContainsKey(limb)) return;
		
		_limbDamage[limb] = new LimbDamage(bruteDamage, burnDamage, toxinDamage, oxygenDamage);
		EmitSignal(SignalName.LimbDamageChanged, limbType, bruteDamage, burnDamage, toxinDamage, oxygenDamage);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncOrganDamageRpc(int organType, float damage, bool isDamaged)
	{
		var organ = (OrganType)organType;
		if (!_organDamage.ContainsKey(organ)) return;
		
		_organDamage[organ] = new OrganDamage(damage, isDamaged);
		EmitSignal(SignalName.OrganDamageChanged, organType, damage, isDamaged);
	}
	
	public float GetLimbDamage(LimbType limb, DamageType damageType)
	{
		if (!_limbDamage.ContainsKey(limb)) return 0f;
		
		var damage = _limbDamage[limb];
		return damageType switch
		{
			DamageType.Brute => damage.BruteDamage,
			DamageType.Burn => damage.BurnDamage,
			DamageType.Toxin => damage.ToxinDamage,
			DamageType.Oxygen => damage.OxygenDamage,
			_ => 0f
		};
	}
	
	public float GetOrganDamage(OrganType organ)
	{
		if (!_organDamage.ContainsKey(organ)) return 0f;
		return _organDamage[organ].Damage;
	}
	
	public bool IsOrganDamaged(OrganType organ)
	{
		if (!_organDamage.ContainsKey(organ)) return false;
		return _organDamage[organ].IsDamaged;
	}
	
	public Dictionary<LimbType, LimbDamage> GetAllLimbDamage() => new(_limbDamage);
	public Dictionary<OrganType, OrganDamage> GetAllOrganDamage() => new(_organDamage);
	
	public override void _ExitTree()
	{
		_isProcessing = false;
		base._ExitTree();
	}
}
