using Godot;

namespace GodotStation.Game.Objects.Items;

// Shared, data-driven item stats - the Resource half of the item identity
// split (see the reclamation plan): Item (the Atom Node) is the live
// world/held instance; ItemData is the stat block many instances can share.
// Ported from the old prototype's Item Resource, minus what moved elsewhere:
// name/description live on the Atom, world icon on Item.IconSheetPath/
// IconState (DMI pipeline), and the old Texture2D+frame-math icon fields
// are gone entirely - DmiSheet owns sprite slicing now.
[GlobalClass]
public partial class ItemData : Resource
{
    public enum Category { Tool, Weapon, Consumable, Clothing, Medical, Misc }

    // Which equipment slot this item can be worn/stored in. Hands are not
    // listed - anything can be held; this is for the worn-equipment slots.
    // Matched to Inventory.EquipmentSlots' real ucfss13-derived slot set;
    // Ears/Pouch stay single values covering both left/right physical
    // slots (many-to-one, same as the old placeholder's convention).
    public enum EquipSlot
    {
        None, Head, Eyes, Mask, Ears, Gloves, Uniform, Jacket, Shoes,
        Id, Belt, Back, Pouch, SuitStorage, Accessory, Handcuffs, Legcuffs,
    }

    [Export] public float Weight = 1.0f;
    [Export] public int MaxStack = 1;
    [Export] public Category ItemCategory = Category.Misc;
    [Export] public EquipSlot WearSlot = EquipSlot.None;

    // DMI icon-state names for on-mob rendering (MobAppearance, Phase 5):
    // state in the item's onmob/inhand sheet when worn / held per hand.
    // Empty = not rendered on the mob.
    [Export] public string WornState = "";
    [Export] public string InhandLeftState = "";
    [Export] public string InhandRightState = "";
    [Export] public string OnMobSheetPath = "";
}
