using Godot;

public partial class GrabItem : Item
{
	public GrabItem()
	{
		ItemName = "Active Grab";
		Icon = GD.Load<Texture2D>("uid://ddo685l40bkjc");
		MaxStack = 1;
	}
}
