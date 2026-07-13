using Godot;
using System.Collections.Generic;

[GlobalClass]
public partial class FrameUpdateManager : Node
{
	[Export] public bool EnableDebugLogging = false;
	[Export] public int MaxCheapUpdatesPerFrame = 1000;
	
	private List<IFrameUpdate> _cheapUpdates = new();
	private List<IFrameUpdate> _updatesToAdd = new();
	private List<IFrameUpdate> _updatesToRemove = new();
	
	[Signal] public delegate void FrameUpdateStatsUpdatedEventHandler(int updateCount, float frameTime);
	
	public override void _Ready()
	{
		base._Ready();
		GD.Print("[FrameUpdateManager] Initialized");
	}
	
	public override void _Process(double delta)
	{
		if (_cheapUpdates.Count == 0) return;
		
		// Process pending additions/removals.
		ProcessPendingChanges();
		
		// Update cheap operations.
		int processedCount = 0;
		for (int i = 0; i < _cheapUpdates.Count && i < MaxCheapUpdatesPerFrame; i++)
		{
			var update = _cheapUpdates[i];
			if (update != null && update.IsActive())
			{
				try
				{
					update.Update((float)delta);
					processedCount++;
				}
				catch (System.Exception e)
				{
					GD.PrintErr($"[FrameUpdateManager] Error updating {update.GetType().Name}: {e.Message}");
				}
			}
		}
		
		if (EnableDebugLogging && processedCount > 0)
		{
			GD.Print($"[FrameUpdateManager] Processed {processedCount}/{_cheapUpdates.Count} updates");
		}
		
		EmitSignal(SignalName.FrameUpdateStatsUpdated, processedCount, (float)delta);
	}
	
	public void RegisterCheapUpdate(IFrameUpdate update)
	{
		if (update == null) return;
		
		if (_cheapUpdates.Contains(update))
		{
			if (EnableDebugLogging)
				GD.Print($"[FrameUpdateManager] Update {update.GetType().Name} already registered");
			return;
		}
		
		_updatesToAdd.Add(update);
		if (EnableDebugLogging)
			GD.Print($"[FrameUpdateManager] Queued registration of {update.GetType().Name}");
	}
	
	public void UnregisterCheapUpdate(IFrameUpdate update)
	{
		if (update == null) return;
		
		if (_cheapUpdates.Contains(update))
		{
			_updatesToRemove.Add(update);
			if (EnableDebugLogging)
				GD.Print($"[FrameUpdateManager] Queued removal of {update.GetType().Name}");
		}
	}
	
	private void ProcessPendingChanges()
	{
		// Add new updates.
		foreach (var update in _updatesToAdd)
		{
			if (!_cheapUpdates.Contains(update))
			{
				_cheapUpdates.Add(update);
				if (EnableDebugLogging)
					GD.Print($"[FrameUpdateManager] Registered {update.GetType().Name}");
			}
		}
		_updatesToAdd.Clear();
		
		// Remove updates.
		foreach (var update in _updatesToRemove)
		{
			_cheapUpdates.Remove(update);
			if (EnableDebugLogging)
				GD.Print($"[FrameUpdateManager] Unregistered {update.GetType().Name}");
		}
		_updatesToRemove.Clear();
	}
	
	public int GetRegisteredCount() => _cheapUpdates.Count;
	
	public void ClearAll()
	{
		_cheapUpdates.Clear();
		_updatesToAdd.Clear();
		_updatesToRemove.Clear();
		if (EnableDebugLogging)
			GD.Print("[FrameUpdateManager] Cleared all updates");
	}
	
	public override void _ExitTree()
	{
		ClearAll();
		base._ExitTree();
	}
}

public interface IFrameUpdate
{
	void Update(float delta);
	
	bool IsActive();
}
