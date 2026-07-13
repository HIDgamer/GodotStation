using Godot;
using System.Linq;

public partial class ToolItem : WeaponItem
{
	[Export] public float ToolCooldown = 1.0f;
	[Export] public float ToolRange = 64.0f;
	[Export] public float PowerConsumption = 5.0f;
	[Export] public string[] ValidTargets = {};
	[Export] public bool CanRepair = false;
	[Export] public bool CanConstruct = false;
	[Export] public bool CanScan = false;
	[Export] public bool CanHack = false;
	[Export] public float ScanRange = 100.0f;
	[Export] public float HackChance = 0.5f;
	
	public void Initialize()
	{
		IsTool = true;
	}
	
	public bool CanUseTool()
	{
		if (IsElectronic && CurrentCharge <= 0) return false;
		return true;
	}
	
	public void UseToolCharge()
	{
		if (IsElectronic)
		{
			UseCharge(PowerConsumption);
		}
	}
	
	public bool IsValidTarget(string targetType)
	{
		if (ValidTargets.Length == 0) return true;
		return ValidTargets.Contains(targetType);
	}
	
	public bool CanRepairObject()
	{
		return CanRepair && ToolType == "repair";
	}
	
	public bool CanConstructObject()
	{
		return CanConstruct && ToolType == "construction";
	}
	
	public bool CanScanObject()
	{
		return CanScan && ToolType == "scanner";
	}
	
	public bool CanHackObject()
	{
		return CanHack && ToolType == "hacking";
	}
}
