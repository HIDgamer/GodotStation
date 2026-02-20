using Godot;
using System.Linq;

public partial class ItemInteraction : Node
{
	private const float PickupRange = 64f;
	
	public override void _UnhandledInput(InputEvent @event)
	{
		if (!(@event is InputEventMouseButton mouseEvent)) return;
		if (mouseEvent.ButtonIndex != MouseButton.Left || !mouseEvent.Pressed) return;
		
		if (Input.IsKeyPressed(Key.Ctrl)) return;
		
		var player = GetLocalPlayer();
		if (player == null) return;
		
		var cam = player.GetNodeOrNull<Camera2D>("PlayerCameraSetup");
		if (cam == null) return;
		
		var worldPos = cam.GetGlobalMousePosition();
		
		var interaction = player.GetNodeOrNull<InteractionComponent>("InteractionComponent");
		bool isInThrowMode = interaction != null && (interaction.IsThrowMode() || interaction.IsLongThrowMode());
		
		if (isInThrowMode)
		{
			var inventory = player.GetNodeOrNull<Inventory>("Inventory");
			if (inventory == null)
			{
				GetViewport().SetInputAsHandled();
				return;
			}
			
			var activeHand = interaction.GetActiveHand();
			var slot = activeHand == 0 ? "left_hand" : "right_hand";
			var heldItem = inventory.GetEquipped(slot);
			
			if (heldItem == null)
			{
				GetViewport().SetInputAsHandled();
				return;
			}
			
			if (interaction.IsLongThrowMode())
			{
				var doAfter = player.GetNodeOrNull<DoAfterComponent>("DoAfterComponent");
				if (doAfter != null)
				{
					var throwPos = worldPos;
					doAfter.StartAction(1.5f, () => 
					{
						if (interaction != null && interaction.IsLongThrowMode())
						{
							interaction.ThrowActive(throwPos);
						}
					});
					doAfter.PlayDoAfterAnimation(1.5f);
				}
				else
				{
					interaction.ThrowActive(worldPos);
				}
			}
			else
			{
				interaction.ThrowActive(worldPos);
			}
			GetViewport().SetInputAsHandled();
			return;
		}
		
		var nearbyItem = FindNearestItem(player, worldPos);
		if (nearbyItem != null)
		{
			nearbyItem.TryPickup(player);
			GetViewport().SetInputAsHandled();
		}
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
