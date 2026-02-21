using Godot;
using System;

[Tool]
public partial class WallLight : Node2D
{
	public enum Direction { North, South, West, East }

	[Export] public Direction LightDirection = Direction.South;
	[Export] public float BaseEnergy = 0.7f;
	[Export] public float ShortCircuitMinTime = 100f;
	[Export] public float ShortCircuitMaxTime = 500f;
	[Export] public float FlickerIntensity = 0.08f;
	[Export] public float FlickerSpeed = 0.8f;
	[Export] public bool EnableFlicker = true;
	[Export] public float BurnoutChance = 0.002f;

	private Sprite2D _lightSprite;
	private PointLight2D _mainLight;
	private GpuParticles2D _particles;
	private VisibleOnScreenNotifier2D _notifier;
	private Timer _shortCircuitTimer;
	private Vector2 _basePosition;
	private bool _isVisible = true;
	private const int TileOffset = 16;
	private const int HalfTileOffset = 8;
	private float _targetEnergy;
	private float _currentEnergy;
	private float _flickerTimer;
	private bool _isBurningOut;
	private bool _isShortCircuiting;
	private float _debugCooldown;

	private bool HasServerAuthority()
	{
		var peer = Multiplayer.MultiplayerPeer;
		return peer != null && Multiplayer.IsServer();
	}

	public override void _Ready()
	{
		_basePosition = Position;
		_lightSprite = GetNode<Sprite2D>("Light");
		_mainLight = GetNode<PointLight2D>("Mainlight");
		_particles = GetNode<GpuParticles2D>("SparkParticles");
		_notifier = GetNode<VisibleOnScreenNotifier2D>("VisibleOnScreenNotifier2D");

		SetDirection(LightDirection);
		_currentEnergy = _targetEnergy = BaseEnergy;
		_mainLight.Energy = BaseEnergy;
		SetupTimers();

		CallDeferred(MethodName.ConnectNotifier);
	}

	private void ConnectNotifier()
	{
		_notifier.ScreenExited += OnScreenExited;
		_notifier.ScreenEntered += OnScreenEntered;
	}

	public override void _Process(double delta)
	{
		if (Engine.IsEditorHint())
		{
			SetDirection(LightDirection);
			return;
		}

		if (_isVisible && EnableFlicker)
		{
			if (!_isBurningOut)
			{
				_flickerTimer -= (float)delta;
				if (_flickerTimer <= 0)
				{
					if (HasServerAuthority() && GD.Randf() < BurnoutChance)
					{
						BurnoutFlicker();
						Rpc(nameof(BurnoutFlickerRpc));
					}
					else
					{
						_targetEnergy = BaseEnergy + (float)GD.RandRange(-FlickerIntensity, FlickerIntensity * 0.3f);
						_flickerTimer = FlickerSpeed * (float)GD.RandRange(0.8, 1.5);
					}
				}
				_currentEnergy = Mathf.Lerp(_currentEnergy, _targetEnergy, (float)delta * 5f);
				_mainLight.Energy = _currentEnergy;
			}
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestBurnoutRpc(NodePath lightPath)
	{
		if (!HasServerAuthority()) return;
		var light = GetNodeOrNull<WallLight>(lightPath);
		if (light != null && !light._isShortCircuiting)
		{
			light.BurnoutFlicker();
			light.Rpc(nameof(BurnoutFlickerRpc));
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BurnoutFlickerRpc()
	{
		BurnoutFlicker();
	}

	private async void BurnoutFlicker()
	{
		_isBurningOut = true;
		_isShortCircuiting = true;
		int flickerCount = GD.RandRange(8, 15);
		
		for (int i = 0; i < flickerCount; i++)
		{
			_mainLight.Energy = GD.Randf() < 0.5f ? 0 : BaseEnergy * (float)GD.RandRange(0.3, 1.2);
			await ToSignal(GetTree().CreateTimer(GD.RandRange(0.05, 0.2)), SceneTreeTimer.SignalName.Timeout);
		}
		
		if (_particles != null)
			_particles.Emitting = true;
		
		_mainLight.Energy = 0;
		await ToSignal(GetTree().CreateTimer(GD.RandRange(0.3, 0.8)), SceneTreeTimer.SignalName.Timeout);
		_mainLight.Energy = BaseEnergy * 0.5f;
		await ToSignal(GetTree().CreateTimer(0.1), SceneTreeTimer.SignalName.Timeout);
		_mainLight.Energy = 0;
		await ToSignal(GetTree().CreateTimer(0.15), SceneTreeTimer.SignalName.Timeout);
		
		_currentEnergy = _targetEnergy = BaseEnergy;
		_mainLight.Energy = BaseEnergy;
		_flickerTimer = FlickerSpeed;
		_isBurningOut = false;
		_isShortCircuiting = false;
	}

	private void SetDirection(Direction dir)
	{
		if (_lightSprite == null) return;

		switch (dir)
		{
			case Direction.North:
				_lightSprite.Frame = 0;
				Position = _basePosition;
				break;
			case Direction.South:
				_lightSprite.Frame = 1;
				Position = _basePosition + new Vector2(0, -TileOffset);
				break;
			case Direction.West:
				_lightSprite.Frame = 2;
				Position = _basePosition + new Vector2(HalfTileOffset, 0);
				break;
			case Direction.East:
				_lightSprite.Frame = 3;
				Position = _basePosition + new Vector2(-HalfTileOffset, 0);
				break;
		}
	}

	private void SetupTimers()
	{
		_shortCircuitTimer = new Timer
		{
			WaitTime = GD.RandRange(ShortCircuitMinTime, ShortCircuitMaxTime),
			OneShot = true
		};
		_shortCircuitTimer.Timeout += OnShortCircuit;
		AddChild(_shortCircuitTimer);
		_shortCircuitTimer.Start();
	}

	private async void OnShortCircuit()
	{
		if (!_isVisible || _mainLight == null) return;

		_targetEnergy = BaseEnergy * 1.8f;
		if (_particles != null)
			_particles.Emitting = true;

		await ToSignal(GetTree().CreateTimer(0.5), SceneTreeTimer.SignalName.Timeout);

		_targetEnergy = BaseEnergy;

		if (_shortCircuitTimer != null)
		{
			_shortCircuitTimer.WaitTime = GD.RandRange(ShortCircuitMinTime, ShortCircuitMaxTime);
			_shortCircuitTimer.Start();
		}
	}

	private void OnScreenExited()
	{
		_isVisible = false;
		SetProcess(false);
		_shortCircuitTimer?.Stop();
	}

	private void OnScreenEntered()
	{
		_isVisible = true;
		SetProcess(true);
		_shortCircuitTimer?.Start();
	}

	public override void _ExitTree()
	{
		if (_notifier != null)
		{
			_notifier.ScreenExited -= OnScreenExited;
			_notifier.ScreenEntered -= OnScreenEntered;
		}
		if (_shortCircuitTimer != null)
		{
			_shortCircuitTimer.Timeout -= OnShortCircuit;
		}
	}
}
