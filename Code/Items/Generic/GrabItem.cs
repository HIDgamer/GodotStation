using Godot;

public partial class GrabItem : Item
{
public GrabItem()
{
	ItemName = "Grab";
	Description = "Actively grabbing someone";
	Icon = GD.Load<Texture2D>("uid://ddo685l40bkjc");
	IconHframes = 3;
	IconVframes = 1;
}
}
