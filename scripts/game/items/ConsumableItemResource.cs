using Godot;

[GlobalClass]
public partial class ConsumableItem : Item
{
	[Export] public float NutritionValue = 10.0f;
	[Export] public float HydrationValue = 5.0f;
	[Export] public float HealAmount = 0.0f;
	
	public ConsumableItem()
	{
		ItemCategory = Category.Consumable;
	}
	
	public void Consume(Mob consumer)
	{
		var health = consumer.GetNodeOrNull<HealthSystem>("HealthSystem");
		if (health != null && HealAmount > 0)
		{
			var healData = new HealingData(HealAmount, ItemName, null);
			health.ApplyHealing(healData);
		}
		
		consumer.ShowChatBubble($"Consumed {ItemName}");
	}
}
