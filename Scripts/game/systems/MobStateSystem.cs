using Godot;

public enum MobState { Standing, Prone, Sleeping, Critical, Dead, Stunned, Grabbed }

public partial class MobStateSystem : Node, IMobSystem
{
	private Mob _owner;
	private MobState _state = MobState.Standing;
	private MobState _stateBeforeCritical = MobState.Standing;
	private float _stateTimer;
	private float _stateDuration;
	
	[Signal] public delegate void StateChangedEventHandler(int newState, int oldState);
	
	public void Init(Mob mob)
	{
		_owner = mob;
		var health = _owner.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (health != null)
		{
			health.CriticalHealth += OnCriticalHealth;
			health.Death += OnDeath;
			health.CriticalRecovered += OnCriticalRecovered;
		}
	}
	
	public void Process(double delta)
	{
		if (_stateDuration <= 0) return;
		
		_stateTimer += (float)delta;
		if (_stateTimer >= _stateDuration)
		{
			if (_state == MobState.Stunned)
				SetState(MobState.Standing);
			_stateDuration = 0;
			_stateTimer = 0;
		}
	}
	
	public void SetState(MobState newState, float duration = 0f)
	{
		if (_state == newState) return;
		
		var oldState = _state;
		if (newState == MobState.Critical)
			_stateBeforeCritical = oldState;
		_state = newState;
		_stateDuration = duration;
		_stateTimer = 0f;
		
		EmitSignal(SignalName.StateChanged, (int)newState, (int)oldState);
		ApplySpriteRotation(newState);
		ApplySpeedModifier(newState);
		
		if (Multiplayer.IsServer())
			Rpc(MethodName.SyncState, (int)newState, duration);
	}
	
	public void HelpUp()
	{
		if (_state != MobState.Prone && _state != MobState.Sleeping)
			return;

		if (_owner.Get("disconnected_peer").AsBool())
			return;

		SetState(MobState.Standing);
	}
	
	public void ForceProne()
	{
		if (_state != MobState.Standing)
			return;
		
		SetState(MobState.Prone);
	}
	
	public void SetStunned(float duration)
	{
		if (_state == MobState.Prone)
		{
			_stateDuration = duration;
			_stateTimer = 0f;
		}
		else
		{
			SetState(MobState.Stunned, duration);
		}
	}
	
	private void ApplySpriteRotation(MobState state)
	{
		var sprite = _owner.GetNodeOrNull<SpriteSystem>("SpriteSystem");
		if (sprite == null) return;
		
		sprite.SetProne(state is MobState.Prone or MobState.Sleeping or MobState.Critical or MobState.Dead);
	}
	
	private void ApplySpeedModifier(MobState state)
	{
		var movement = _owner.GetNodeOrNull<MovementController>("MovementController");
		if (movement == null) return;
		
		float mod = state switch
		{
			MobState.Prone => 0.5f,
			MobState.Sleeping or MobState.Critical or MobState.Dead or MobState.Stunned or MobState.Grabbed => 0f,
			_ => 1f
		};
		movement.SetSpeedMultiplier(mod);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncState(int state, float duration)
	{
		var newState = (MobState)state;
		if (_state == newState) return;
		
		var oldState = _state;
		_state = newState;
		_stateDuration = duration;
		_stateTimer = 0f;
		
		EmitSignal(SignalName.StateChanged, (int)newState, (int)oldState);
		ApplySpriteRotation(newState);
		ApplySpeedModifier(newState);
	}
	
	public MobState GetState() => _state;
	public bool CanMove() => _state is MobState.Standing or MobState.Prone;
	public bool IsIncapacitated() => _state is MobState.Sleeping or MobState.Critical or MobState.Dead or MobState.Stunned or MobState.Grabbed;

	private void OnCriticalRecovered()
	{
		if (_state != MobState.Critical) return;
		if (_stateBeforeCritical == MobState.Standing)
			SetState(MobState.Standing);
		else if (_stateBeforeCritical == MobState.Prone || _stateBeforeCritical == MobState.Sleeping)
			SetState(_stateBeforeCritical);
	}

	private void OnCriticalHealth()
	{
		SetState(MobState.Critical);
	}

	private void OnDeath()
	{
		SetState(MobState.Dead);
	}
	
	public void Cleanup()
	{
		var health = _owner.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (health != null)
		{
			health.CriticalHealth -= OnCriticalHealth;
			health.Death -= OnDeath;
			health.CriticalRecovered -= OnCriticalRecovered;
		}
	}
}
