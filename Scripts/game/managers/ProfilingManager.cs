using Godot;
using System;
using System.Collections.Generic;

[GlobalClass]
public partial class ProfilingManager : Node
{
[Export] public bool EnableProfiling = true;
[Export] public float ProfileReportInterval = 5.0f; // Changed to 5 seconds as requested
[Export] public int SkipThresholdAlert = 100;
[Export] public bool EnablePerformanceHeatmaps = true;
[Export] public bool EnableMemoryMonitoring = true;
[Export] public bool EnableDetailedResourceMonitoring = true; // New: Monitor all resource usage
[Export] public bool EnableNodeCountMonitoring = true; // New: Monitor node counts
[Export] public bool EnableNetworkMonitoring = true; // New: Monitor network usage
	
	private Scheduler _scheduler;
	private FrameUpdateManager _frameUpdateManager;
	private BatchManager _batchManager;
	
private float _reportTimer = 0f;
private ProfilingStats _currentStats = new();
private Dictionary<string, SystemStats> _systemStats = new();
private List<PerformanceAlert> _alerts = new();
private Dictionary<string, ResourceUsage> _resourceUsage = new(); // New: Track resource usage
private Dictionary<string, NodeCount> _nodeCounts = new(); // New: Track node counts
	
	[Signal] public delegate void PerformanceAlertEventHandler(string alertType, string message, float severity);
	[Signal] public delegate void ProfilingReportEventHandler();
	
	public override void _Ready()
	{
		base._Ready();
		
		_scheduler = GetNodeOrNull<Scheduler>("/root/Scheduler");
		_frameUpdateManager = GetNodeOrNull<FrameUpdateManager>("/root/FrameUpdateManager");
		_batchManager = GetNodeOrNull<BatchManager>("/root/BatchManager");
		
		if (EnableProfiling)
		{
			GD.Print("[ProfilingManager] Profiling enabled");
			
			// Connect to scheduler signals for monitoring.
			if (_scheduler != null)
			{
				_scheduler.SchedulerUpdateStarted += OnSchedulerUpdateStarted;
				_scheduler.SchedulerUpdateCompleted += OnSchedulerUpdateCompleted;
			}
			
			// Connect to frame update manager signals.
			if (_frameUpdateManager != null)
			{
				_frameUpdateManager.FrameUpdateStatsUpdated += OnFrameUpdateStatsUpdated;
			}
		}
	}
	
	public override void _Process(double delta)
	{
		if (!EnableProfiling) return;
		
		_reportTimer += (float)delta;
		
		if (_reportTimer >= ProfileReportInterval)
		{
			GenerateReport();
			_reportTimer = 0f;
		}
		
		// Check for performance alerts.
		CheckPerformanceAlerts();
	}
	
	public ProfilingStats GetCurrentStats() => _currentStats;
	
	public Dictionary<string, SystemStats> GetSystemStats() => _systemStats;
	
	public List<PerformanceAlert> GetRecentAlerts() => _alerts;
	
public void ClearAlerts()
{
	_alerts.Clear();
}

public void ResetStats()
{
	_currentStats = new ProfilingStats();
	_systemStats.Clear();
	_alerts.Clear();
	_resourceUsage.Clear();
	_nodeCounts.Clear();
}

// New methods for resource monitoring.
public void AddResourceUsage(string resourceName, float usage, string unit = "MB")
{
	if (!_resourceUsage.ContainsKey(resourceName))
	{
		_resourceUsage[resourceName] = new ResourceUsage { Name = resourceName, Unit = unit };
	}
	
	var resource = _resourceUsage[resourceName];
	resource.CurrentUsage = usage;
	resource.PeakUsage = Math.Max(resource.PeakUsage, usage);
	resource.TotalUsage += usage;
	resource.SampleCount++;
}

public void AddNodeCount(string nodeType, int count)
{
	if (!_nodeCounts.ContainsKey(nodeType))
	{
		_nodeCounts[nodeType] = new NodeCount { NodeType = nodeType };
	}
	
	var nodeCount = _nodeCounts[nodeType];
	nodeCount.CurrentCount = count;
	nodeCount.PeakCount = Math.Max(nodeCount.PeakCount, count);
	nodeCount.TotalCount += count;
	nodeCount.SampleCount++;
}

public Dictionary<string, ResourceUsage> GetResourceUsage() => _resourceUsage;
public Dictionary<string, NodeCount> GetNodeCounts() => _nodeCounts;
	
	private void OnSchedulerUpdateStarted(int updateCount)
	{
		_currentStats.SchedulerUpdateStarted(updateCount);
	}
	
	private void OnSchedulerUpdateCompleted(int processedCount)
	{
		_currentStats.SchedulerUpdateCompleted(processedCount);
		
		// Track system-specific stats.
		if (_scheduler != null)
		{
			var registeredCount = _scheduler.GetRegisteredCount();
			var pendingUpdates = _scheduler.GetPendingUpdates();
			
			_currentStats.TotalRegisteredItems = registeredCount;
			_currentStats.TotalPendingUpdates = pendingUpdates;
			
			// Calculate skip/delay rates.
			if (registeredCount > 0)
			{
				float skipRate = (float)(registeredCount - processedCount) / registeredCount;
				_currentStats.AverageSkipRate = (_currentStats.AverageSkipRate + skipRate) / 2f;
				
				if (skipRate > 0.1f) // 10% skip rate
				{
					_currentStats.HighSkipRateFrames++;
				}
			}
		}
	}
	
	private void OnFrameUpdateStatsUpdated(int updateCount, float frameTime)
	{
		_currentStats.FrameUpdateStats(updateCount, frameTime);
		
		// Track batch stats if available.
		if (_batchManager != null)
		{
			_currentStats.TotalBatches = _batchManager.GetTotalBatches();
			_currentStats.ActiveBatches = _batchManager.GetActiveBatches();
			_currentStats.TotalBatchedUpdates = _batchManager.GetTotalUpdates();
		}
	}
	
private void GenerateReport()
{
	// Calculate averages.
	_currentStats.CalculateAverages();
	
	// Generate performance insights.
	var insights = GeneratePerformanceInsights();
	
	// Generate detailed resource report.
	var resourceReport = GenerateResourceReport();
	
	// Log performance report.
	GD.Print($"[ProfilingManager] PERFORMANCE REPORT:");
	GD.Print($"  Time: {DateTime.Now.ToString("HH:mm:ss")}");
	GD.Print($"");
	GD.Print($"  FRAME PERFORMANCE:");
	GD.Print($"    - Frame Updates: {_currentStats.TotalFrameUpdates} (avg: {_currentStats.AverageFrameTime:F4}s)");
	GD.Print($"    - Scheduler Updates: {_currentStats.TotalSchedulerUpdates} (avg: {_currentStats.AverageSchedulerTime:F4}s)");
	GD.Print($"    - Skip Rate: {_currentStats.AverageSkipRate:P2}");
	GD.Print($"    - High Skip Rate Frames: {_currentStats.HighSkipRateFrames}");
	GD.Print($"");
	GD.Print($"  RESOURCE USAGE:");
	GD.Print(resourceReport);
	GD.Print($"");
	GD.Print($"  MEMORY USAGE: {_currentStats.PeakMemoryUsage:F1} MB");
	GD.Print($"  PERFORMANCE INSIGHTS: {insights}");
	
	EmitSignal(SignalName.ProfilingReport);
}

private string GenerateResourceReport()
{
	var report = new System.Text.StringBuilder();
	
	// System resource usage.
	if (_resourceUsage.Count > 0)
	{
		foreach (var kvp in _resourceUsage)
		{
			var resource = kvp.Value;
			var avgUsage = resource.TotalUsage / Math.Max(resource.SampleCount, 1);
			report.AppendLine($"    - {resource.Name}: {resource.CurrentUsage:F2}{resource.Unit} (peak: {resource.PeakUsage:F2}{resource.Unit}, avg: {avgUsage:F2}{resource.Unit})");
		}
	}
	
	// Node counts.
	if (_nodeCounts.Count > 0)
	{
		report.AppendLine($"    - NODE COUNTS:");
		foreach (var kvp in _nodeCounts)
		{
			var nodeCount = kvp.Value;
			var avgCount = nodeCount.TotalCount / Math.Max(nodeCount.SampleCount, 1);
			report.AppendLine($"      - {nodeCount.NodeType}: {nodeCount.CurrentCount} (peak: {nodeCount.PeakCount}, avg: {avgCount:F0})");
		}
	}
	
	// Overall node count.
	var totalNodes = CountNodes(GetTree().Root);
	report.AppendLine($"    - TOTAL NODES: {totalNodes}");
	
	return report.ToString();
}
	
	private string GeneratePerformanceInsights()
	{
		var insights = new List<string>();
		
		if (_currentStats.AverageSkipRate > 0.2f)
		{
			insights.Add("High skip rate detected - consider reducing update frequency or increasing frame capacity");
		}
		
		if (_currentStats.HighSkipRateFrames > 10)
		{
			insights.Add("Frequent frame drops detected - system may be overloaded");
		}
		
		if (_currentStats.PeakMemoryUsage > 1000) // 1GB
		{
			insights.Add("High memory usage detected - consider optimizing data structures");
		}
		
		if (_currentStats.TotalBatches > 50)
		{
			insights.Add("Many batches detected - consider merging smaller batches");
		}
		
		return insights.Count > 0 ? string.Join(", ", insights) : "System running within normal parameters";
	}
	
private void CheckPerformanceAlerts()
{
	if (_scheduler == null) return;
	
	var registeredCount = _scheduler.GetRegisteredCount();
	var pendingUpdates = _scheduler.GetPendingUpdates();
	
	// Check skip threshold.
	if (pendingUpdates > SkipThresholdAlert)
	{
		var alert = new PerformanceAlert
		{
			Type = "HighPendingUpdates",
			Message = $"Too many pending updates: {pendingUpdates} (threshold: {SkipThresholdAlert})",
			Severity = Math.Min(pendingUpdates / (float)SkipThresholdAlert, 5.0f),
			Timestamp = Time.GetUnixTimeFromSystem()
		};
		
		AddAlert(alert);
	}
	
	// Check memory usage.
	if (EnableMemoryMonitoring)
	{
		var memoryUsage = OS.GetStaticMemoryUsage() / (1024.0f * 1024.0f); // MB
		if (memoryUsage > 1000) // 1GB
		{
			var alert = new PerformanceAlert
			{
				Type = "HighMemoryUsage",
				Message = $"High memory usage: {memoryUsage:F1} MB",
				Severity = Math.Min(memoryUsage / 1000.0f, 5.0f),
				Timestamp = Time.GetUnixTimeFromSystem()
			};
			
			AddAlert(alert);
		}
	}
	
	// Check resource usage alerts.
	if (EnableDetailedResourceMonitoring)
	{
		CheckResourceUsageAlerts();
	}
	
	// Check node count alerts.
	if (EnableNodeCountMonitoring)
	{
		CheckNodeCountAlerts();
	}
}

private void CheckResourceUsageAlerts()
{
	foreach (var kvp in _resourceUsage)
	{
		var resource = kvp.Value;
		
		// Alert on high resource usage.
		if (resource.CurrentUsage > 100)
		{
			var alert = new PerformanceAlert
			{
				Type = "HighResourceUsage",
				Message = $"High {resource.Name} usage: {resource.CurrentUsage:F2}{resource.Unit}",
				Severity = Math.Min(resource.CurrentUsage / 100.0f, 5.0f),
				Timestamp = Time.GetUnixTimeFromSystem()
			};
			
			AddAlert(alert);
		}
	}
}

	private void CheckNodeCountAlerts()
{
	var totalNodes = CountNodes(GetTree().Root);
	
	// Alert on too many nodes.
	if (totalNodes > 10000)
	{
		var alert = new PerformanceAlert
		{
			Type = "HighNodeCount",
			Message = $"Too many nodes: {totalNodes}",
			Severity = Math.Min(totalNodes / 10000.0f, 5.0f),
			Timestamp = Time.GetUnixTimeFromSystem()
		};
		
		AddAlert(alert);
	}
}

private void CheckGPUMemoryUsage()
{
	// Check for high texture memory usage.
	if (_resourceUsage.ContainsKey("TextureMemory"))
	{
		var textureUsage = _resourceUsage["TextureMemory"];
		if (textureUsage.CurrentUsage > 500) // 500MB threshold
		{
			var alert = new PerformanceAlert
			{
				Type = "HighGPUMemoryUsage",
				Message = $"High GPU texture memory usage: {textureUsage.CurrentUsage:F1} MB",
				Severity = Math.Min(textureUsage.CurrentUsage / 500.0f, 5.0f),
				Timestamp = Time.GetUnixTimeFromSystem()
			};
			
			AddAlert(alert);
		}
	}
	
	// Check for too many textures.
	var textureCount = 0;
	foreach (var kvp in _resourceUsage)
	{
		if (kvp.Key.Contains("Texture") || kvp.Key.Contains("Sprite"))
			textureCount++;
	}
	
	if (textureCount > 100)
	{
		var alert = new PerformanceAlert
		{
			Type = "TooManyTextures",
			Message = $"Too many textures loaded: {textureCount}",
			Severity = Math.Min(textureCount / 100.0f, 5.0f),
			Timestamp = Time.GetUnixTimeFromSystem()
		};
		
		AddAlert(alert);
	}
}

private int CountNodes(Node node)
{
	if (node == null) return 0;
	
	int count = 1;
	foreach (var child in node.GetChildren())
	{
		count += CountNodes(child as Node);
	}
	return count;
}
	
	private void AddAlert(PerformanceAlert alert)
	{
		_alerts.Add(alert);
		EmitSignal(SignalName.PerformanceAlert, alert.Type, alert.Message, alert.Severity);
		
		GD.Print($"[ProfilingManager] ALERT: {alert.Type} - {alert.Message} (severity: {alert.Severity:F1})");
	}
	
	public override void _ExitTree()
	{
		if (_scheduler != null)
		{
			_scheduler.SchedulerUpdateStarted -= OnSchedulerUpdateStarted;
			_scheduler.SchedulerUpdateCompleted -= OnSchedulerUpdateCompleted;
		}
		
		if (_frameUpdateManager != null)
		{
			_frameUpdateManager.FrameUpdateStatsUpdated -= OnFrameUpdateStatsUpdated;
		}
		
		base._ExitTree();
	}
}

public class ProfilingStats
{
	public int TotalFrameUpdates { get; set; }
	public int TotalSchedulerUpdates { get; set; }
	public int TotalRegisteredItems { get; set; }
	public int TotalPendingUpdates { get; set; }
	public int TotalBatches { get; set; }
	public int ActiveBatches { get; set; }
	public int TotalBatchedUpdates { get; set; }
	public int HighSkipRateFrames { get; set; }
	
	public float TotalFrameTime { get; set; }
	public float TotalSchedulerTime { get; set; }
	public float AverageFrameTime { get; set; }
	public float AverageSchedulerTime { get; set; }
	public float AverageSkipRate { get; set; }
	public float PeakMemoryUsage { get; set; }
	
	public void SchedulerUpdateStarted(int updateCount)
	{
		// Track start time if needed.
	}
	
	public void SchedulerUpdateCompleted(int processedCount)
	{
		TotalSchedulerUpdates++;
		// Calculate time if we had start time tracking.
	}
	
	public void FrameUpdateStats(int updateCount, float frameTime)
	{
		TotalFrameUpdates++;
		TotalFrameTime += frameTime;
		AverageFrameTime = TotalFrameTime / TotalFrameUpdates;
		
		// Track memory usage.
		var memoryUsage = OS.GetStaticMemoryUsage() / (1024.0f * 1024.0f);
		PeakMemoryUsage = Math.Max(PeakMemoryUsage, memoryUsage);
	}
	
	public void CalculateAverages()
	{
		if (TotalFrameUpdates > 0)
		{
			AverageFrameTime = TotalFrameTime / TotalFrameUpdates;
		}
		
		if (TotalSchedulerUpdates > 0)
		{
			AverageSchedulerTime = TotalSchedulerTime / TotalSchedulerUpdates;
		}
	}
}

public class SystemStats
{
	public string SystemName { get; set; }
	public int UpdateCount { get; set; }
	public float TotalUpdateTime { get; set; }
	public float AverageUpdateTime { get; set; }
	public int SkipCount { get; set; }
	public float SkipRate { get; set; }
}

public class PerformanceAlert
{
	public string Type { get; set; }
	public string Message { get; set; }
	public float Severity { get; set; } // 0.0 to 5.0
	public double Timestamp { get; set; }
}

// New classes for resource monitoring.
public class ResourceUsage
{
	public string Name { get; set; }
	public string Unit { get; set; }
	public float CurrentUsage { get; set; }
	public float PeakUsage { get; set; }
	public float TotalUsage { get; set; }
	public int SampleCount { get; set; }
}

public class NodeCount
{
	public string NodeType { get; set; }
	public int CurrentCount { get; set; }
	public int PeakCount { get; set; }
	public int TotalCount { get; set; }
	public int SampleCount { get; set; }
}
