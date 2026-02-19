using Godot;

[GlobalClass]
public partial class ClothingItem : Item
{
	public enum ClothingSlot { Head, Eyes, Mask, Ears, Gloves, Uniform, Armor, Shoes, Belt, Back, Pouch }
	
	[Export] public ClothingSlot Slot;
	[Export] public float ArmorMelee = 0f;
	[Export] public float ArmorBullet = 0f;
	[Export] public float ArmorLaser = 0f;
	[Export] public float ArmorBomb = 0f;
	[Export] public float ArmorBio = 0f;
	[Export] public float ArmorRad = 0f;
	[Export] public float ArmorFire = 0f;
	[Export] public float ArmorAcid = 0f;
	[Export] public float SpeedModifier = 0f;
	[Export] public int StorageSlots = 0;
	[Export] public Texture2D WornTexture;
}
