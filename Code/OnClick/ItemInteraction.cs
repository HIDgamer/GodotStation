using Godot;
using System.Linq;

public partial class ItemInteraction : Node
{
	private const float PickupRange = 64f;
	
	public override void _Input(InputEvent @event)
	{
		if (!(@event is InputEventMouseButton mouseEvent)) return;
		if (mouseEvent.ButtonIndex != MouseButton.Left || !mouseEvent.Pressed) return;
		
		var player = GetLocalPlayer();
		if (player == null) return;
		
		var cam = player.GetNodeOrNull<Camera2D>("PlayerCameraSetup");
		if (cam == null) return;
		
		var worldPos = cam.GetGlobalMousePosition();
		
		var interaction = player.GetNodeOrNull<InteractionComponent>("InteractionComponent");
		if (interaction?.IsThrowMode() == true)
		{
			interaction.ThrowActive(worldPos);
			return;
		}
		
		var nearbyItem = FindNearestItem(player, worldPos);
		nearbyItem?.TryPickup(player);
	}
	
	private Mob GetLocalPlayer()
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null) return null;
		
		foreach (var child in world.GetChildren())
		{
			if (child is Mob mob && mob.IsMultiplayerAuthority())
				return mob;
		}
		
		return null;
	}
	
	private WorldItem FindNearestItem(Mob player, Vector2 clickPos)
	{
		var items = GetTree().GetNodesInGroup("WorldItems")
			.Cast<WorldItem>()
			.Where(item => player.GlobalPosition.DistanceTo(item.GlobalPosition) <= PickupRange)
			.OrderBy(item => item.GlobalPosition.DistanceTo(clickPos));
		
		foreach (var item in items)
		{
			var localPos = item.ToLocal(clickPos);
			if (item.IsPixelAtPosition(localPos))
				return item;
		}
		
		return null;
	}
}
