using Godot;
using System;

public partial class FireSystem : Node, IMobSystem, ISchedulable
{
	[Export] public float MaxFireStacks = 10f;
	[Export] public float FireDamagePerStack = 2.0f;
	[Export] public float FireStackDecayRate = 0.5f;
	[Export] public float FireResistance = 0.0f;
	[Export] public float WaterExtinguishRate = 5.0f;
	
	// Scheduler configuration.
	[Export] public float SchedulerUpdateInterval = 1.0f; // Update every 1 second
	[Export] public int SchedulerPriority = 7; // Medium-high priority
	[Export] public bool SchedulerUpdateOnRegister = false;
	[Export] public bool EnableDebugLogging = false;
	
	private Mob _mob;
	private float _fireStacks = 0f;
	private bool _isOnFire = false;
	private bool _isProcessing;
	private Scheduler _scheduler;
	
	[Signal] public delegate void FireStateChangedEventHandler(bool isOnFire);
	[Signal] public delegate void FireStacksChangedEventHandler(float fireStacks);
	
	public override void _Ready()
	{
		base._Ready();
		InitializeFire();
	}
	
	public void Init(Mob mob)
	{
		_mob = mob;
		InitializeFire();
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
				GD.Print("[FireSystem] Registered with scheduler");
		}
		else
		{
			GD.PrintErr("[FireSystem] No scheduler found in scene or autoloads!");
		}
	}
	
	public void Process(double delta)
	{
		if (!_isProcessing || _mob == null) return;
	}
	
	public void ScheduledUpdate(float delta, WorldSnapshot snapshot)
	{
		if (!_isProcessing || _mob == null) return;
		
		UpdateFire(delta);
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
	
	private void InitializeFire()
	{
		_fireStacks = 0f;
		_isOnFire = false;
		EmitSignal(SignalName.FireStateChanged, _isOnFire);
		EmitSignal(SignalName.FireStacksChanged, _fireStacks);
	}
	
	private void UpdateFire(float delta)
	{
		// Decay fire stacks over time.
		if (_fireStacks > 0)
		{
			_fireStacks = Mathf.Max(0, _fireStacks - FireStackDecayRate * delta);
			EmitSignal(SignalName.FireStacksChanged, _fireStacks);
		}
		
		// Check if we should be on fire.
		bool shouldBeOnFire = _fireStacks > 0;
		if (_isOnFire != shouldBeOnFire)
		{
			_isOnFire = shouldBeOnFire;
			EmitSignal(SignalName.FireStateChanged, _isOnFire);
			
			if (_isOnFire)
			{
				ShowFireMessage("You are on fire!");
			}
			else
			{
				ShowFireMessage("You are no longer on fire.");
			}
		}
		
		// Apply fire damage over time.
		if (_isOnFire)
		{
			ApplyFireDamage();
		}
	}
	
	private void ApplyFireDamage()
	{
		var healthSystem = _mob.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (healthSystem == null) return;
		
		float damage = FireDamagePerStack * _fireStacks * (1.0f - FireResistance);
		healthSystem.ApplyDamage(DamageType.Burn, damage, "fire", this);
	}
	
	public void TryIgnite(float fireStacks)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (fireStacks > 0)
		{
			_fireStacks = Mathf.Min(_fireStacks + fireStacks, MaxFireStacks);
			EmitSignal(SignalName.FireStacksChanged, _fireStacks);
			
			if (!_isOnFire)
			{
				_isOnFire = true;
				EmitSignal(SignalName.FireStateChanged, _isOnFire);
				ShowFireMessage("You are on fire!");
			}
			
			Rpc(MethodName.SyncFireStateRpc, _fireStacks, _isOnFire);
		}
	}
	
	public void Extinguish()
	{
		if (!Multiplayer.IsServer()) return;
		
		if (_isOnFire)
		{
			_fireStacks = 0f;
			_isOnFire = false;
			EmitSignal(SignalName.FireStateChanged, _isOnFire);
			EmitSignal(SignalName.FireStacksChanged, _fireStacks);
			ShowFireMessage("You have been extinguished.");
			Rpc(MethodName.SyncFireStateRpc, _fireStacks, _isOnFire);
		}
	}
	
	public void ApplyWaterExtinguish(float waterAmount)
	{
		if (!Multiplayer.IsServer()) return;
		
		if (_fireStacks > 0)
		{
			_fireStacks = Mathf.Max(0, _fireStacks - waterAmount * WaterExtinguishRate);
			EmitSignal(SignalName.FireStacksChanged, _fireStacks);
			
			if (_fireStacks <= 0 && _isOnFire)
			{
				_isOnFire = false;
				EmitSignal(SignalName.FireStateChanged, _isOnFire);
				ShowFireMessage("You have been extinguished.");
			}
			
			Rpc(MethodName.SyncFireStateRpc, _fireStacks, _isOnFire);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncFireStateRpc(float fireStacks, bool isOnFire)
	{
		_fireStacks = fireStacks;
		_isOnFire = isOnFire;
		EmitSignal(SignalName.FireStateChanged, _isOnFire);
		EmitSignal(SignalName.FireStacksChanged, _fireStacks);
	}
	
	public void SetFireResistance(float resistance)
	{
		FireResistance = Mathf.Clamp(resistance, 0.0f, 1.0f);
	}
	
	private void ShowFireMessage(string message)
	{
		_mob?.ShowChatBubble(message);
	}
	
	public bool IsOnFire() => _isOnFire;
	public float GetFireStacks() => _fireStacks;
	public float GetMaxFireStacks() => MaxFireStacks;
	
	// Ischedulable interface implementation.
	public string SchedulerId => _mob?.GetPlayerName() + "_FireSystem" ?? "Unknown_FireSystem";
	public float UpdateInterval => SchedulerUpdateInterval;
	public int Priority => SchedulerPriority;
	public bool UpdateOnRegister => SchedulerUpdateOnRegister;
	public bool IsActive => _isProcessing && _mob != null;
	public bool NeedsProcessing => _isProcessing && _mob != null && _fireStacks > 0;
	
	public override void _ExitTree()
	{
		Cleanup();
		base._ExitTree();
	}
}
