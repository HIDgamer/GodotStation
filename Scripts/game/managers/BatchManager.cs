using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

[GlobalClass]
public partial class BatchManager : Node
{
	[Export] public bool EnableBatching = true;
	[Export] public int BatchSize = 100;
	[Export] public bool EnableSpatialBatching = true;
	[Export] public bool EnableTypeBatching = true;
	[Export] public bool EnablePriorityBatching = true;
	[Export] public int MaxBatchesPerFrame = 3;
	
	private FrameUpdateManager _frameUpdateManager;
	private List<UpdateBatch> _batches = new();
	private Dictionary<string, UpdateBatch> _batchLookup = new();
	private int _currentBatchIndex = 0;
	private int _frameCounter = 0;
	
	[Signal] public delegate void BatchStatsUpdatedEventHandler(int totalBatches, int activeBatches, int processedThisFrame);
	
	public override void _Ready()
	{
		base._Ready();
		_frameUpdateManager = GetNodeOrNull<FrameUpdateManager>("/root/FrameUpdateManager");
		
		if (_frameUpdateManager != null)
		{
			GD.Print("[BatchManager] Initialized with batching enabled");
		}
		else
		{
			GD.PrintErr("[BatchManager] FrameUpdateManager not found - batching disabled");
			EnableBatching = false;
		}
	}
	
	public void RegisterBatchedUpdate(IFrameUpdate update, string batchKey = null)
	{
		if (!EnableBatching || _frameUpdateManager == null)
		{
			_frameUpdateManager?.RegisterCheapUpdate(update);
			return;
		}
		
		string key = batchKey ?? GenerateBatchKey(update);
		UpdateBatch batch = GetOrCreateBatch(key);
		
		if (batch.AddUpdate(update))
		{
			// Only register the batch wrapper, not individual updates.
			if (!batch.IsRegistered)
			{
				_frameUpdateManager.RegisterCheapUpdate(batch);
				batch.IsRegistered = true;
			}
		}
	}
	
	public void UnregisterBatchedUpdate(IFrameUpdate update, string batchKey = null)
	{
		if (!EnableBatching)
		{
			_frameUpdateManager?.UnregisterCheapUpdate(update);
			return;
		}
		
		string key = batchKey ?? GenerateBatchKey(update);
		if (_batchLookup.TryGetValue(key, out var batch))
		{
			batch.RemoveUpdate(update);
			
			// Unregister batch if empty.
			if (batch.UpdateCount == 0 && batch.IsRegistered)
			{
				_frameUpdateManager.UnregisterCheapUpdate(batch);
				batch.IsRegistered = false;
				_batches.Remove(batch);
				_batchLookup.Remove(key);
			}
		}
	}
	
	public void ClearAllBatches()
	{
		if (_frameUpdateManager != null)
		{
			foreach (var batch in _batches)
			{
				if (batch.IsRegistered)
				{
					_frameUpdateManager.UnregisterCheapUpdate(batch);
				}
			}
		}
		
		_batches.Clear();
		_batchLookup.Clear();
		_currentBatchIndex = 0;
	}
	
	public int GetTotalBatches() => _batches.Count;
	public int GetActiveBatches() => _batches.FindAll(b => b.IsRegistered).Count;
	public int GetTotalUpdates() => _batches.Sum(b => b.UpdateCount);
	
	private UpdateBatch GetOrCreateBatch(string key)
	{
		if (_batchLookup.TryGetValue(key, out var batch))
		{
			return batch;
		}
		
		batch = new UpdateBatch(key, BatchSize);
		_batches.Add(batch);
		_batchLookup[key] = batch;
		
		return batch;
	}
	
	private string GenerateBatchKey(IFrameUpdate update)
	{
		if (EnableSpatialBatching)
		{
			// Try to get spatial information from the update object.
			if (update is Node node && node.GetParent() is Node parentNode)
			{
				return $"spatial_{parentNode.GetPath()}";
			}
		}
		
		if (EnableTypeBatching)
		{
			return $"type_{update.GetType().Name}";
		}
		
		if (EnablePriorityBatching)
		{
			// Try to get priority information.
			if (update is ISchedulable schedulable)
			{
				return $"priority_{schedulable.Priority}";
			}
		}
		
		return "default";
	}
	
	public override void _Process(double delta)
	{
		if (!EnableBatching || _batches.Count == 0) return;
		
		_frameCounter++;
		int processedThisFrame = 0;
		
		// Process batches in round-robin fashion.
		for (int i = 0; i < MaxBatchesPerFrame && processedThisFrame < _batches.Count; i++)
		{
			var batch = _batches[_currentBatchIndex];
			
			if (batch.IsRegistered && batch.UpdateCount > 0)
			{
				// Process this batch's updates for this frame.
				batch.ProcessFrame((float)delta, _frameCounter);
				processedThisFrame++;
			}
			
			// Move to next batch.
			_currentBatchIndex = (_currentBatchIndex + 1) % _batches.Count;
		}
		
		EmitSignal(SignalName.BatchStatsUpdated, _batches.Count, GetActiveBatches(), processedThisFrame);
	}
	
	public override void _ExitTree()
	{
		ClearAllBatches();
		base._ExitTree();
	}
}

public class UpdateBatch : IFrameUpdate
{
	public string BatchKey { get; }
	public int BatchSize { get; }
	public bool IsRegistered { get; set; } = false;
	public int UpdateCount => _updates.Count;
	
	private List<IFrameUpdate> _updates = new();
	private int _currentUpdateIndex = 0;
	private int _updatesProcessedThisFrame = 0;
	
	public UpdateBatch(string batchKey, int batchSize)
	{
		BatchKey = batchKey;
		BatchSize = batchSize;
	}
	
	public bool AddUpdate(IFrameUpdate update)
	{
		if (_updates.Contains(update)) return false;
		
		_updates.Add(update);
		return true;
	}
	
	public bool RemoveUpdate(IFrameUpdate update)
	{
		return _updates.Remove(update);
	}
	
	public bool IsActive() => _updates.Count > 0;
	
	public void Update(float delta)
	{
		// This method is called by frameupdatemanager but we handle the actual processing.
		// In processframe to control how many updates we do per frame.
	}
	
	public void ProcessFrame(float delta, int frameCounter)
	{
		// Process a subset of updates this frame to distribute load.
		int updatesToProcess = Math.Min(BatchSize, _updates.Count - _currentUpdateIndex);
		
		for (int i = 0; i < updatesToProcess; i++)
		{
			var update = _updates[_currentUpdateIndex];
			if (update.IsActive())
			{
				update.Update(delta);
				_updatesProcessedThisFrame++;
			}
			
			_currentUpdateIndex = (_currentUpdateIndex + 1) % _updates.Count;
		}
		
		// Reset for next frame if we've processed all updates.
		if (_currentUpdateIndex == 0)
		{
			_updatesProcessedThisFrame = 0;
		}
	}
}

public static class BatchManagerExtensions
{
	public static void RegisterBatchedUpdate(this IFrameUpdate update, string batchKey = null)
	{
		var tree = Engine.GetMainLoop() as SceneTree;
		var batchManager = tree?.CurrentScene?.GetNodeOrNull<BatchManager>("/root/BatchManager");
		batchManager?.RegisterBatchedUpdate(update, batchKey);
	}
	
	public static void UnregisterBatchedUpdate(this IFrameUpdate update, string batchKey = null)
	{
		var tree = Engine.GetMainLoop() as SceneTree;
		var batchManager = tree?.CurrentScene?.GetNodeOrNull<BatchManager>("/root/BatchManager");
		batchManager?.UnregisterBatchedUpdate(update, batchKey);
	}
}
