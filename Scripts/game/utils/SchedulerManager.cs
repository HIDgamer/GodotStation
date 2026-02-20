using Godot;

[GlobalClass]
public partial class SchedulerManager : Node
{
	[Export] public Scheduler Scheduler;
	[Export] public bool EnableDebugLogging = true;
	[Export] public int MaxUpdatesPerFrame = 10;
	[Export] public float TargetFrameRate = 60.0f;
	[Export] public bool EnableDynamicAdjustment = true;
	[Export] public float TargetFPS = 60.0f;
	[Export] public float FPSVarianceThreshold = 5.0f;
	[Export] public int MinUpdatesPerFrame = 1;
	[Export] public int MaxUpdatesPerFrameDynamic = 20;
	
	[Signal] public delegate void SchedulerStatsUpdatedEventHandler(int registeredCount, int pendingUpdates, int processedCount);
	
	private int _totalProcessedCount = 0;
	private int _frameCount = 0;
	private float _updateTimeAccumulator = 0f;
	
	public override void _Ready()
	{
		base._Ready();
		
		Scheduler = GetNodeOrNull<Scheduler>("/root/Scheduler");
		
		if (Scheduler == null)
		{
			Scheduler = GetTree().GetFirstNodeInGroup("Scheduler") as Scheduler;
		}
		
		if (Scheduler == null)
		{
			GD.PrintErr("[SchedulerManager] No scheduler found in scene or autoloads!");
		}
		else
		{
			if (EnableDebugLogging)
				GD.Print("[SchedulerManager] Scheduler found and connected.");
		}
		
		if (Scheduler != null)
		{
			// Configure scheduler.
			Scheduler.MaxUpdatesPerFrame = MaxUpdatesPerFrame;
			Scheduler.TargetFrameRate = TargetFrameRate;
			Scheduler.EnableDebugLogging = EnableDebugLogging;
			
			// Connect to scheduler signals.
			Scheduler.SchedulerUpdateStarted += OnSchedulerUpdateStarted;
			Scheduler.SchedulerUpdateCompleted += OnSchedulerUpdateCompleted;
			Scheduler.ItemRegistered += OnItemRegistered;
			Scheduler.ItemUnregistered += OnItemUnregistered;
			
			if (EnableDebugLogging)
				GD.Print($"[SchedulerManager] Scheduler configured: MaxUpdatesPerFrame={MaxUpdatesPerFrame}, TargetFrameRate={TargetFrameRate}");
		}
		else
		{
			GD.PrintErr("[SchedulerManager] No scheduler found in scene!");
		}
	}
	
	public void ConfigureScheduler(int maxUpdatesPerFrame, float targetFrameRate, bool enableDebugLogging)
	{
		MaxUpdatesPerFrame = maxUpdatesPerFrame;
		TargetFrameRate = targetFrameRate;
		EnableDebugLogging = enableDebugLogging;
		
		if (Scheduler != null)
		{
			Scheduler.MaxUpdatesPerFrame = maxUpdatesPerFrame;
			Scheduler.TargetFrameRate = targetFrameRate;
			Scheduler.EnableDebugLogging = enableDebugLogging;
		}
	}
	
	public void GetSchedulerStats(out int registeredCount, out int pendingUpdates, out int processedCount)
	{
		registeredCount = Scheduler?.GetRegisteredCount() ?? 0;
		pendingUpdates = Scheduler?.GetPendingUpdates() ?? 0;
		processedCount = _totalProcessedCount;
	}
	
	public void ForceUpdateAll()
	{
		Scheduler?.ForceUpdateAll();
	}
	
	public void ClearAll()
	{
		Scheduler?.Clear();
		_totalProcessedCount = 0;
	}
	
	private void OnSchedulerUpdateStarted(int updateCount)
	{
		// Removed debug print as requested.
	}
	
	private void OnSchedulerUpdateCompleted(int processedCount)
	{
		_totalProcessedCount += processedCount;
		_frameCount++;
		_updateTimeAccumulator += 1.0f / TargetFrameRate;
		
		if (EnableDebugLogging && _frameCount % 60 == 0) // Log every 60 frames
		{
			GD.Print($"[SchedulerManager] Stats: Registered={Scheduler.GetRegisteredCount()}, Pending={Scheduler.GetPendingUpdates()}, TotalProcessed={_totalProcessedCount}");
		}
		
		EmitSignal(SignalName.SchedulerStatsUpdated, 
			Scheduler.GetRegisteredCount(), 
			Scheduler.GetPendingUpdates(), 
			_totalProcessedCount);
	}
	
	private void OnItemRegistered(string itemId)
	{
		if (EnableDebugLogging)
			GD.Print($"[SchedulerManager] Item registered: {itemId}");
	}
	
	private void OnItemUnregistered(string itemId)
	{
		if (EnableDebugLogging)
			GD.Print($"[SchedulerManager] Item unregistered: {itemId}");
	}
	
	public override void _ExitTree()
	{
		if (Scheduler != null)
		{
			Scheduler.SchedulerUpdateStarted -= OnSchedulerUpdateStarted;
			Scheduler.SchedulerUpdateCompleted -= OnSchedulerUpdateCompleted;
			Scheduler.ItemRegistered -= OnItemRegistered;
			Scheduler.ItemUnregistered -= OnItemUnregistered;
		}
		base._ExitTree();
	}
}
