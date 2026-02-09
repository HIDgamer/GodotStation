using Godot;

/// Base tool item data
[GlobalClass]
public partial class ToolItem : Item
{
	public enum ToolType
	{
		Wrench,
		Screwdriver,
		Cutter,
		Welder,
		Multitool,
		Scanner,
		Medical,
		Construction,
		Utility,
		Other
	}

	[Export] public ToolType Type = ToolType.Utility;
	[Export] public float UseTime = 0.5f;
	[Export] public int Durability = -1;
	[Export] public int DurabilityCost = 1;
	[Export] public bool RequiresPower = false;
	[Export] public float PowerCost = 0f;
	[Export] public bool RequiresTwoHands = false;
	[Export] public string UseVerb = "use";

	public ToolItem()
	{
		ItemCategory = Category.Tool;
	}

	public bool CanUse()
	{
		return Durability != 0;
	}

	public void SpendDurability(int amount = -1)
	{
		if (Durability < 0) return;
		int cost = amount < 0 ? DurabilityCost : amount;
		Durability = Mathf.Max(0, Durability - cost);
	}
}
