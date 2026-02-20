using Godot;

public partial class ItemStack
{
	public Item ItemData { get; private set; }
	public int Quantity { get; set; }
	
	public ItemStack(Item item, int quantity = 1)
	{
		ItemData = item;
		Quantity = quantity;
	}
	
	public bool CanStackWith(ItemStack other)
	{
		return other != null && 
		       other.ItemData == ItemData && 
		       Quantity < ItemData.MaxStack;
	}
	
	public int AddQuantity(int amount)
	{
		int space = ItemData.MaxStack - Quantity;
		int toAdd = Mathf.Min(amount, space);
		Quantity += toAdd;
		return amount - toAdd;
	}
}
