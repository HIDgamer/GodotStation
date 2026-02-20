using Godot;
using System;
using System.Collections.Generic;
using System.Threading;

public interface ISchedulable
{
	string SchedulerId { get; }
	
	float UpdateInterval { get; }
	
	int Priority { get; }
	
	bool UpdateOnRegister { get; }
	
	bool IsActive { get; }
	
	bool NeedsProcessing { get; }
	
	void ScheduledUpdate(float delta, WorldSnapshot snapshot);
}
public class WorldSnapshot
{
	public readonly float Time;
	public readonly Dictionary<string, object> Data;
	
	// Global data tracking.
	public readonly Dictionary<string, object> TileChanges = new();
	public readonly Dictionary<string, object> AtmosphericData = new();
	public readonly Dictionary<string, object> PowerNetworkData = new();
	public readonly Dictionary<string, object> EconomicData = new();
	public readonly Dictionary<string, object> EntityDistribution = new();
	
	public WorldSnapshot(float time)
	{
		Time = time;
		Data = new Dictionary<string, object>();
	}
	
	public void AddData(string key, object value)
	{
		Data[key] = value;
	}
	
	public T GetData<T>(string key)
	{
		return Data.TryGetValue(key, out var value) ? (T)value : default;
	}
	
	public bool HasData(string key)
	{
		return Data.ContainsKey(key);
	}
	
	// Tile change tracking.
	public void AddTileChange(string tileKey, object changeData)
	{
		TileChanges[tileKey] = changeData;
	}
	
	public void AddAtmosphericData(string region, object data)
	{
		AtmosphericData[region] = data;
	}
	
	public void AddPowerNetworkData(string networkId, object data)
	{
		PowerNetworkData[networkId] = data;
	}
	
	public void AddEconomicData(string marketId, object data)
	{
		EconomicData[marketId] = data;
	}
	
	public void AddEntityDistribution(string region, int count)
	{
		EntityDistribution[region] = count;
	}
	
	// Batch data operations.
	public void MergeTileChanges(Dictionary<string, object> changes)
	{
		foreach (var change in changes)
		{
			TileChanges[change.Key] = change.Value;
		}
	}
	
	public void MergeAtmosphericData(Dictionary<string, object> data)
	{
		foreach (var item in data)
		{
			AtmosphericData[item.Key] = item.Value;
		}
	}
	
	public void MergePowerNetworkData(Dictionary<string, object> data)
	{
		foreach (var item in data)
		{
			PowerNetworkData[item.Key] = item.Value;
		}
	}
	
	public void MergeEconomicData(Dictionary<string, object> data)
	{
		foreach (var item in data)
		{
			EconomicData[item.Key] = item.Value;
		}
	}
	
	public void MergeEntityDistribution(Dictionary<string, object> distribution)
	{
		foreach (var item in distribution)
		{
			EntityDistribution[item.Key] = item.Value;
		}
	}
}
public partial class Scheduler : Node
{
	[Export] public int MaxUpdatesPerFrame = 10;
	[Export] public float TargetFrameRate = 60.0f;
	[Export] public bool EnableDebugLogging = false;
	[Export] public bool EnableDynamicAdjustment = true;
	[Export] public float MinFrameTimeThreshold = 0.016f; // 16ms threshold for 60 FPS
	[Export] public int MinUpdatesPerFrame = 1;
	[Export] public int MaxUpdatesPerFrameForExpensive = 5;
	
	private PriorityQueue<ScheduledItem> _priorityQueue;
	private Dictionary<string, ScheduledItem> _registeredItems;
	private List<ScheduledItem> _updateBuffer;
	private List<string> _removalBuffer;
	private float _timeAccumulator = 0f;
	private float _frameTime = 0f;
	private WorldSnapshot _currentSnapshot;
	private bool _isUpdating = false;
	
	[Signal] public delegate void SchedulerUpdateStartedEventHandler(int updateCount);
	[Signal] public delegate void SchedulerUpdateCompletedEventHandler(int processedCount);
	[Signal] public delegate void ItemRegisteredEventHandler(string itemId);
	[Signal] public delegate void ItemUnregisteredEventHandler(string itemId);
	
	public override void _Ready()
	{
		base._Ready();
		
		_priorityQueue = new PriorityQueue<ScheduledItem>();
		_registeredItems = new Dictionary<string, ScheduledItem>();
		_updateBuffer = new List<ScheduledItem>();
		_removalBuffer = new List<string>();
		_frameTime = 1.0f / (float)TargetFrameRate;
		
		// Removed debug print as requested.
	}
	
	public override void _Process(double delta)
	{
		if (_isUpdating)
		{
			GD.PrintErr("[Scheduler] Warning: _Process called while updating. This should not happen.");
			return;
		}
		
		_timeAccumulator += (float)delta;
		
		// Only process if we have time accumulated and items to update.
		if (_timeAccumulator >= _frameTime && _priorityQueue.Count > 0)
		{
			ProcessScheduledUpdates();
			_timeAccumulator = 0f;
		}
		
		// Process any pending removals.
		ProcessRemovals();
	}
	
	public void Register(ISchedulable schedulable)
	{
		if (schedulable == null)
		{
			GD.PrintErr("[Scheduler] Cannot register null schedulable object");
			return;
		}
		
		if (string.IsNullOrEmpty(schedulable.SchedulerId))
		{
			GD.PrintErr("[Scheduler] Cannot register object with null or empty SchedulerId");
			return;
		}
		
		if (_registeredItems.ContainsKey(schedulable.SchedulerId))
		{
			GD.Print($"[Scheduler] Object with ID '{schedulable.SchedulerId}' is already registered");
			return;
		}
		
		var item = new ScheduledItem(schedulable);
		
		// Set initial update time based on updateonregister.
		if (schedulable.UpdateOnRegister)
		{
			item.NextUpdateTime = 0f; // Update immediately
		}
		else
		{
			item.NextUpdateTime = (float)Time.GetUnixTimeFromSystem() + schedulable.UpdateInterval;
		}
		
		_registeredItems[schedulable.SchedulerId] = item;
		_priorityQueue.Enqueue(item);
		
		EmitSignal(SignalName.ItemRegistered, schedulable.SchedulerId);
		
		if (EnableDebugLogging)
			GD.Print($"[Scheduler] Registered: {schedulable.SchedulerId} (priority: {schedulable.Priority}, interval: {schedulable.UpdateInterval}s)");
	}
	
	public void Unregister(string schedulerId)
	{
		if (string.IsNullOrEmpty(schedulerId))
		{
			GD.PrintErr("[Scheduler] Cannot unregister with null or empty schedulerId");
			return;
		}
		
		if (_isUpdating)
		{
			// Defer removal if we're currently updating.
			if (!_removalBuffer.Contains(schedulerId))
				_removalBuffer.Add(schedulerId);
			return;
		}
		
		if (_registeredItems.TryGetValue(schedulerId, out var item))
		{
			_registeredItems.Remove(schedulerId);
			_priorityQueue.Remove(item);
			EmitSignal(SignalName.ItemUnregistered, schedulerId);
			
			if (EnableDebugLogging)
				GD.Print($"[Scheduler] Unregistered: {schedulerId}");
		}
		else
		{
			GD.Print($"[Scheduler] Attempted to unregister non-existent item: {schedulerId}");
		}
	}
	
	public void Unregister(ISchedulable schedulable)
	{
		if (schedulable != null)
			Unregister(schedulable.SchedulerId);
	}
	
	public int GetRegisteredCount() => _registeredItems.Count;
	
	public int GetPendingUpdates() => _priorityQueue.Count;
	
	public void ForceUpdateAll()
	{
		if (_priorityQueue.Count == 0) return;
		
		var snapshot = CreateSnapshot();
		var itemsToUpdate = new List<ScheduledItem>();
		
		// Collect all items.
		while (_priorityQueue.Count > 0)
		{
			itemsToUpdate.Add(_priorityQueue.Dequeue());
		}
		
		// Update all items.
		foreach (var item in itemsToUpdate)
		{
			if (item.Schedulable.IsActive)
			{
				try
				{
					item.Schedulable.ScheduledUpdate(_frameTime, snapshot);
					item.LastUpdateTime = snapshot.Time;
					item.NextUpdateTime = snapshot.Time + item.Schedulable.UpdateInterval;
				}
				catch (Exception e)
				{
					GD.PrintErr($"[Scheduler] Error updating {item.Schedulable.SchedulerId}: {e.Message}");
				}
			}
			_priorityQueue.Enqueue(item);
		}
		
		if (EnableDebugLogging)
			GD.Print($"[Scheduler] Force updated {itemsToUpdate.Count} items");
	}
	
	public void Clear()
	{
		_registeredItems.Clear();
		_priorityQueue.Clear();
		_removalBuffer.Clear();
		
		if (EnableDebugLogging)
			GD.Print("[Scheduler] Cleared all registered items");
	}
	
	private void ProcessScheduledUpdates()
	{
		if (_priorityQueue.Count == 0) return;
		
		_isUpdating = true;
		var snapshot = CreateSnapshot();
		int processedCount = 0;
		
		EmitSignal(SignalName.SchedulerUpdateStarted, Math.Min(MaxUpdatesPerFrame, _priorityQueue.Count));
		
		try
		{
			_updateBuffer.Clear();
			
			// Collect items that need updating (up to MaxUpdatesPerFrame).
			while (_updateBuffer.Count < MaxUpdatesPerFrame && _priorityQueue.Count > 0)
			{
				var item = _priorityQueue.Peek();
				
				// Check if item is due for update and is active.
				if (item.NextUpdateTime <= snapshot.Time && item.Schedulable.IsActive)
				{
					_priorityQueue.Dequeue(); // Remove from queue
					_updateBuffer.Add(item);
				}
				else
				{
					break; // No more items ready for update
				}
			}
			
			// Process collected updates.
			foreach (var item in _updateBuffer)
			{
				try
				{
					item.Schedulable.ScheduledUpdate(_frameTime, snapshot);
					processedCount++;
					
					// Schedule next update.
					item.LastUpdateTime = snapshot.Time;
					item.NextUpdateTime = snapshot.Time + item.Schedulable.UpdateInterval;
					
					// Re-queue if still active.
					if (item.Schedulable.IsActive)
						_priorityQueue.Enqueue(item);
				}
				catch (Exception e)
				{
					GD.PrintErr($"[Scheduler] Error updating {item.Schedulable.SchedulerId}: {e.Message}");
					// Still re-queue the item to avoid losing it, but log the error.
					if (item.Schedulable.IsActive)
						_priorityQueue.Enqueue(item);
				}
			}
			
			// Handle any items that missed their update window.
			HandleMissedUpdates(snapshot);
		}
		finally
		{
			_isUpdating = false;
		EmitSignal(SignalName.SchedulerUpdateCompleted, processedCount);
		
		// Removed debug print as requested.
		}
	}
	
	private void HandleMissedUpdates(WorldSnapshot snapshot)
	{
		// Re-queue any items that were skipped due to frame capacity.
		// They will be rescheduled for the next available slot.
		var tempBuffer = new List<ScheduledItem>();
		
		while (_priorityQueue.Count > 0)
		{
			var item = _priorityQueue.Peek();
			
			// If item was due but not processed, reschedule it.
			if (item.NextUpdateTime <= snapshot.Time && item.Schedulable.IsActive)
			{
				_priorityQueue.Dequeue();
				item.NextUpdateTime = snapshot.Time + item.Schedulable.UpdateInterval;
				tempBuffer.Add(item);
			}
			else
			{
				break;
			}
		}
		
		// Re-add rescheduled items to queue.
		foreach (var item in tempBuffer)
		{
			_priorityQueue.Enqueue(item);
		}
	}
	
	private WorldSnapshot CreateSnapshot()
	{
		_currentSnapshot = new WorldSnapshot((float)Time.GetUnixTimeFromSystem());
		
		// Add global snapshot data.
		_currentSnapshot.AddData("frameTime", _frameTime);
		_currentSnapshot.AddData("registeredCount", _registeredItems.Count);
		_currentSnapshot.AddData("pendingUpdates", _priorityQueue.Count);
		
		return _currentSnapshot;
	}
	
	private void ProcessRemovals()
	{
		if (_removalBuffer.Count > 0)
		{
			foreach (var id in _removalBuffer)
			{
				if (_registeredItems.TryGetValue(id, out var item))
				{
					_registeredItems.Remove(id);
					_priorityQueue.Remove(item);
					EmitSignal(SignalName.ItemUnregistered, id);
				}
			}
			_removalBuffer.Clear();
		}
	}
	
	public override void _ExitTree()
	{
		Clear();
		base._ExitTree();
	}
}

internal class ScheduledItem : IComparable<ScheduledItem>
{
	public ISchedulable Schedulable { get; }
	public float LastUpdateTime { get; set; }
	public float NextUpdateTime { get; set; }
	
	public ScheduledItem(ISchedulable schedulable)
	{
		Schedulable = schedulable;
		LastUpdateTime = 0f;
		NextUpdateTime = schedulable.UpdateInterval;
	}
	
	// Priority queue ordering: higher priority first, then earlier update time.
	public int CompareTo(ScheduledItem other)
	{
		// First compare by priority (higher priority first).
		int priorityComparison = other.Schedulable.Priority.CompareTo(Schedulable.Priority);
		if (priorityComparison != 0)
			return priorityComparison;
		
		// Then compare by next update time.
		return NextUpdateTime.CompareTo(other.NextUpdateTime);
	}
}

internal class PriorityQueue<T> where T : IComparable<T>
{
	private List<T> _heap = new List<T>();
	
	public int Count => _heap.Count;
	
	public void Enqueue(T item)
	{
		_heap.Add(item);
		HeapifyUp(_heap.Count - 1);
	}
	
	public T Dequeue()
	{
		if (_heap.Count == 0)
			throw new InvalidOperationException("Queue is empty");
		
		T root = _heap[0];
		T last = _heap[_heap.Count - 1];
		_heap.RemoveAt(_heap.Count - 1);
		
		if (_heap.Count > 0)
		{
			_heap[0] = last;
			HeapifyDown(0);
		}
		
		return root;
	}
	
	public T Peek()
	{
		if (_heap.Count == 0)
			throw new InvalidOperationException("Queue is empty");
		
		return _heap[0];
	}
	
	public void Remove(T item)
	{
		int index = _heap.IndexOf(item);
		if (index == -1) return;
		
		if (index == _heap.Count - 1)
		{
			_heap.RemoveAt(_heap.Count - 1);
		}
		else
		{
			T last = _heap[_heap.Count - 1];
			_heap.RemoveAt(_heap.Count - 1);
			_heap[index] = last;
			HeapifyDown(index);
		}
	}
	
	public void Clear()
	{
		_heap.Clear();
	}
	
	private void HeapifyUp(int index)
	{
		while (index > 0)
		{
			int parent = (index - 1) / 2;
			if (_heap[index].CompareTo(_heap[parent]) >= 0)
				break;
			
			Swap(index, parent);
			index = parent;
		}
	}
	
	private void HeapifyDown(int index)
	{
		int left = 2 * index + 1;
		int right = 2 * index + 2;
		int smallest = index;
		
		if (left < _heap.Count && _heap[left].CompareTo(_heap[smallest]) < 0)
			smallest = left;
		
		if (right < _heap.Count && _heap[right].CompareTo(_heap[smallest]) < 0)
			smallest = right;
		
		if (smallest != index)
		{
			Swap(index, smallest);
			HeapifyDown(smallest);
		}
	}
	
	private void Swap(int i, int j)
	{
		T temp = _heap[i];
		_heap[i] = _heap[j];
		_heap[j] = temp;
	}
}
