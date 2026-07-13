using Godot;
using System;

public partial class DoAfterComponent : Node, IMobSystem
{
	private Mob _owner;
	private bool _active;
	private float _timer;
	private float _duration;
	private Action _onComplete;
	private Action _onCancel;
	private Vector2 _startPos;
	private Sprite2D _animationSprite;
	
	private const float MaxMoveDist = 16f;
	
	[Signal] public delegate void DoAfterStartedEventHandler();
	[Signal] public delegate void DoAfterCompletedEventHandler();
	[Signal] public delegate void DoAfterCancelledEventHandler();
	
	public void Init(Mob mob) => _owner = mob;
	
	public void Process(double delta)
	{
		if (!_active) return;
		
		if (_owner.GlobalPosition.DistanceTo(_startPos) > MaxMoveDist)
		{
			Cancel("Moved too far");
			return;
		}
		
		var state = _owner.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (state?.IsIncapacitated() == true)
		{
			Cancel("Incapacitated");
			return;
		}
		
		_timer += (float)delta;
		if (_timer >= _duration)
			Complete();
	}
	
	public bool StartAction(float duration, Action onComplete, Action onCancel = null)
	{
		if (_active) return false;
		
		_active = true;
		_timer = 0f;
		_duration = duration;
		_onComplete = onComplete;
		_onCancel = onCancel;
		_startPos = _owner.GlobalPosition;
		
		EmitSignal(SignalName.DoAfterStarted);
		return true;
	}
	
	public void Cancel(string reason = "")
	{
		if (!_active) return;
		
		_active = false;
		_onCancel?.Invoke();
		EmitSignal(SignalName.DoAfterCancelled);
	}
	
	private void Complete()
	{
		if (!_active) return;
		
		_active = false;
		_onComplete?.Invoke();
		EmitSignal(SignalName.DoAfterCompleted);
	}
	
	public bool IsDoingAction() => _active;
	public float GetProgress() => _active ? _timer / _duration : 0f;
	public void Cleanup() => Cancel();
	
	public void PlayDoAfterAnimation(float duration, string animationType = "default")
	{
		if (_animationSprite != null)
		{
			_animationSprite.QueueFree();
			_animationSprite = null;
		}
		
		_animationSprite = new Sprite2D
		{
			ZIndex = 1000,
			Position = new Vector2(0, -20),
			Texture = ResourceLoader.Load<Texture2D>("uid://cqglc2mfqbup1"),
			Hframes = 20,
			Vframes = 1,
			Frame = 0
		};
		
		_owner.AddChild(_animationSprite);
		
		var tween = _owner.CreateTween();
		tween.TweenProperty(_animationSprite, "frame", 19, duration);
		tween.TweenCallback(Callable.From(() => 
		{
			if (_animationSprite != null && IsInstanceValid(_animationSprite))
				_animationSprite.QueueFree();
			_animationSprite = null;
		}));
	}
	
	public void StopDoAfterAnimation()
	{
		if (_animationSprite != null && IsInstanceValid(_animationSprite))
		{
			_animationSprite.QueueFree();
		}
		_animationSprite = null;
	}
}
