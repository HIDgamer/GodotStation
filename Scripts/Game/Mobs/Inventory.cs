using System.Collections.Generic;
using Godot;
using GodotStation.Game.Objects.Items;

namespace GodotStation.Game.Mobs;

// Full equipment + storage inventory, ported from the old prototype's
// 20-slot/weight/equipment-dict Inventory and rebuilt on the new item
// identity split: slots hold Item NODES (live instances), never shared
// Resources - the old version stored Item Resources, which is exactly the
// "genuine rewrite inside the port" the reclamation plan called out.
//
// Connection rebuild vs. old: IMobSystem -> IMobComponent; no internal
// RPCs (server-authoritative state; PlayerMob relays HUD-relevant changes
// over its frozen Hud ABI); GrabItem/food-quality handling deferred to the
// Grab/Food ports (P2/P3). Hand order convention: index 0 = RIGHT hand,
// 1 = LEFT (matches the HUD's R|L layout and the existing Hud ABI - the
// old prototype used 0=left, deliberately not carried over).
public partial class Inventory : Node, IMobComponent
{
    [Export] public int MaxStorageSlots = 20;
    [Export] public float MaxWeight = 50.0f;

    // Fired on any change a hand-slot HUD widget cares about (swap, store,
    // take) - one coarse signal; listeners re-read both hands.
    [Signal] public delegate void HandsChangedEventHandler();

    // Fired when a worn-equipment slot changes (equip/unequip).
    [Signal] public delegate void EquipmentChangedEventHandler(string slot);

    // Fired when the general storage list changes (add/remove).
    [Signal] public delegate void StorageChangedEventHandler();

    public const string SlotRightHand = "right_hand";
    public const string SlotLeftHand = "left_hand";

    // Worn-equipment slot names - matched to ucfss13's real slot set
    // (WEAR_HEAD/WEAR_EYES/WEAR_FACE/WEAR_L_EAR+WEAR_R_EAR/WEAR_HANDS/
    // WEAR_BODY/WEAR_JACKET/WEAR_FEET/WEAR_ID/WEAR_WAIST/WEAR_BACK/
    // WEAR_L_STORE+WEAR_R_STORE/WEAR_J_STORE/WEAR_ACCESSORY/WEAR_HANDCUFFS/
    // WEAR_LEGCUFFS), studied as design reference only - not ported from
    // its source. "jacket" replaces the placeholder "armor" name (the
    // real slot holds the whole outer suit, not just armor plating), and
    // ear/pouch slots are spelled singular (ear_left/ear_right,
    // pouch_left/pouch_right) to match everywhere else's naming.
    public static readonly string[] EquipmentSlots =
    {
        "head", "eyes", "mask", "ear_left", "ear_right", "gloves",
        "uniform", "jacket", "shoes", "id", "belt", "back",
        "pouch_left", "pouch_right", "suit_storage", "accessory",
        "handcuffs", "legcuffs",
    };

    // Auto-equip priority for TryEquipActiveHandAnySlot (mirrors ucfss13's
    // equip_to_appropriate_slot) - handcuffs/legcuffs are deliberately
    // excluded, those only ever get set by a dedicated restrain action,
    // never by "equip whatever's in my hand".
    private static readonly string[] AutoEquipPriority =
    {
        "head", "eyes", "mask", "ear_left", "ear_right", "uniform",
        "jacket", "gloves", "shoes", "belt", "back", "id",
        "suit_storage", "pouch_left", "pouch_right", "accessory",
    };

    private readonly Dictionary<string, Item?> _equipped = new();
    private readonly List<Item> _storage = new();
    private Mob? _owner;

    public int ActiveHand { get; private set; }

    public void Initialize(Mob mob)
    {
        _owner = mob;
        _equipped.TryAdd(SlotRightHand, null);
        _equipped.TryAdd(SlotLeftHand, null);
        foreach (var slot in EquipmentSlots) _equipped.TryAdd(slot, null);
    }

    public void Cleanup() { }

    // ── Hands (API shape kept from the pre-reclamation Inventory so
    //    PlayerMob's verbs and the Hud ABI stay untouched) ─────────────────
    private static string HandSlot(int index) => index == 0 ? SlotRightHand : SlotLeftHand;

    public Item? GetHand(int index) => _equipped.GetValueOrDefault(HandSlot(index));

    public Item? GetActiveItem() => GetHand(ActiveHand);

    public bool HasFreeHand() => GetHand(0) == null || GetHand(1) == null;

    public void SwitchHand()
    {
        ActiveHand = 1 - ActiveHand;
        EmitSignal(SignalName.HandsChanged);
    }

    // Stores into the active hand, falling back to the other hand.
    public bool TryStore(Item item)
    {
        var slot = GetHand(ActiveHand) == null ? ActiveHand : (GetHand(1 - ActiveHand) == null ? 1 - ActiveHand : -1);
        if (slot < 0) return false;

        _equipped[HandSlot(slot)] = item;
        EmitSignal(SignalName.HandsChanged);
        return true;
    }

    public Item? TakeActiveItem()
    {
        var item = GetHand(ActiveHand);
        if (item == null) return null;

        _equipped[HandSlot(ActiveHand)] = null;
        EmitSignal(SignalName.HandsChanged);
        return item;
    }

    // ── Worn equipment ─────────────────────────────────────────────────────
    public Item? GetEquipped(string slot) => _equipped.GetValueOrDefault(slot);

    public bool CanEquip(Item item, string slot)
    {
        if (!_equipped.ContainsKey(slot) || _equipped[slot] != null) return false;
        var wear = item.Data?.WearSlot ?? ItemData.EquipSlot.None;
        return slot switch
        {
            "head" => wear == ItemData.EquipSlot.Head,
            "eyes" => wear == ItemData.EquipSlot.Eyes,
            "mask" => wear == ItemData.EquipSlot.Mask,
            "ear_left" or "ear_right" => wear == ItemData.EquipSlot.Ears,
            "gloves" => wear == ItemData.EquipSlot.Gloves,
            "uniform" => wear == ItemData.EquipSlot.Uniform,
            "jacket" => wear == ItemData.EquipSlot.Jacket,
            "shoes" => wear == ItemData.EquipSlot.Shoes,
            "id" => wear == ItemData.EquipSlot.Id,
            "belt" => wear == ItemData.EquipSlot.Belt,
            "back" => wear == ItemData.EquipSlot.Back,
            "pouch_left" or "pouch_right" => wear == ItemData.EquipSlot.Pouch,
            "suit_storage" => wear == ItemData.EquipSlot.SuitStorage,
            "accessory" => wear == ItemData.EquipSlot.Accessory,
            "handcuffs" => wear == ItemData.EquipSlot.Handcuffs,
            "legcuffs" => wear == ItemData.EquipSlot.Legcuffs,
            _ => false,
        };
    }

    // Tries each slot the active-hand item could go in, in priority order,
    // and equips into the first free match - the "click self with item"
    // auto-equip path (ucfss13's equip_to_appropriate_slot).
    public bool TryEquipActiveHandAnySlot()
    {
        var item = GetActiveItem();
        if (item == null) return false;

        foreach (var slot in AutoEquipPriority)
        {
            if (CanEquip(item, slot)) return EquipActiveHand(slot);
        }
        return false;
    }

    // Moves the active-hand item into a worn slot. Caller (PlayerMob /
    // InventoryWindow flow) is responsible for visibility/reparenting.
    public bool EquipActiveHand(string slot)
    {
        var item = GetActiveItem();
        if (item == null || !CanEquip(item, slot)) return false;

        _equipped[HandSlot(ActiveHand)] = null;
        _equipped[slot] = item;
        EmitSignal(SignalName.HandsChanged);
        EmitSignal(SignalName.EquipmentChanged, slot);
        return true;
    }

    // Moves a worn item back into a free hand.
    public bool UnequipToHand(string slot)
    {
        var item = GetEquipped(slot);
        if (item == null || !HasFreeHand()) return false;

        _equipped[slot] = null;
        TryStore(item);
        EmitSignal(SignalName.EquipmentChanged, slot);
        return true;
    }

    // ── General storage (backpack-style; stacking arrives with the
    //    ItemStack port) ────────────────────────────────────────────────────
    public IReadOnlyList<Item> Storage => _storage;

    public float GetTotalWeight()
    {
        var total = 0f;
        foreach (var item in _storage) total += item.Weight;
        foreach (var equipped in _equipped.Values)
        {
            if (equipped != null) total += equipped.Weight;
        }
        return total;
    }

    public bool TryAddToStorage(Item item)
    {
        if (_storage.Count >= MaxStorageSlots) return false;
        if (GetTotalWeight() + item.Weight > MaxWeight) return false;

        _storage.Add(item);
        EmitSignal(SignalName.StorageChanged);
        return true;
    }

    public bool RemoveFromStorage(Item item)
    {
        if (!_storage.Remove(item)) return false;
        EmitSignal(SignalName.StorageChanged);
        return true;
    }
}
