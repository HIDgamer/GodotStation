using Godot;
public partial class FoodItemInstance : Node, ISchedulable
{
	[Export] public FoodItem FoodData;
	
	// Scheduler configuration.
	[Export] public float SchedulerUpdateInterval = 1.0f; // Update every 1 second
	[Export] public int SchedulerPriority = 3; // Low priority
	[Export] public bool SchedulerUpdateOnRegister = false;
	[Export] public bool EnableDebugLogging = false;
	
	private Scheduler _scheduler;
	private float _spoilTimer = 0f;
	private bool _isSpoiled = false;
	
	[Signal] public delegate void SpoiledEventHandler();
	
	public override void _Ready()
	{
		base._Ready();
		Initialize();
	}
	
	public void Initialize()
	{
		if (FoodData == null)
		{
			GD.PrintErr("[FoodItemInstance] No FoodData assigned!");
			return;
		}
		
		_spoilTimer = FoodData.SpoilTime;
		_isSpoiled = false;
		
		_scheduler = GetNodeOrNull<Scheduler>("/root/Scheduler");
		
		if (_scheduler == null)
		{
			_scheduler = GetTree().GetFirstNodeInGroup("Scheduler") as Scheduler;
		}
		
		if (_scheduler != null)
		{
			_scheduler.Register(this);
			if (EnableDebugLogging)
				GD.Print("[FoodItemInstance] Registered with scheduler");
		}
		else
		{
			GD.PrintErr("[FoodItemInstance] No scheduler found in scene or autoloads!");
		}
	}
	
	public void ScheduledUpdate(float delta, WorldSnapshot snapshot)
	{
		if (!_isSpoiled && FoodData != null)
		{
			_spoilTimer -= delta;
			if (_spoilTimer <= 0)
			{
				Spoil();
			}
		}
	}
	
	private void Spoil()
	{
		if (_isSpoiled) return;
		
		_isSpoiled = true;
		FoodData.QualityMultiplier = 0.1f; // Spoiled food has very low quality
		FoodData.HealingAmount *= 0.1f; // Spoiled food heals less
		FoodData.PainReduction = 0f; // Spoiled food doesn't reduce pain
		
		EmitSignal(SignalName.Spoiled);
	}
	
	public void Cleanup()
	{
		// Unregister from scheduler.
		if (_scheduler != null)
		{
			_scheduler.Unregister(this);
		}
	}
	
	public bool IsSpoiled() => _isSpoiled;
	public float GetSpoilProgress() => Mathf.Clamp(1.0f - (_spoilTimer / FoodData.SpoilTime), 0f, 1f);
	
	public string SchedulerId => GetPath() + "_FoodItemInstance";
	public float UpdateInterval => SchedulerUpdateInterval;
	public int Priority => SchedulerPriority;
	public bool UpdateOnRegister => SchedulerUpdateOnRegister;
	public bool IsActive => !IsQueuedForDeletion() && !_isSpoiled && _spoilTimer > 0;
	public bool NeedsProcessing => !_isSpoiled && _spoilTimer > 0;
	
	public override void _ExitTree()
	{
		Cleanup();
		base._ExitTree();
	}
}
