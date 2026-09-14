using Godot;
using GodotStation.Core.Assets;
using GodotStation.Core.World;
using GodotStation.Game.Objects;

namespace GodotStation.Game.Objects.Items;

// One generic scene (Scenes/Game/Item.tscn) covers every item for now -
// which icon it shows is exported data, not a subclass, per the roadmap's
// composition-over-inheritance rule (a pistol vs. a toolbox is the same
// script with different IconSheetPath/IconState, not two scripts). Reserve
// actual subclassing for items with genuinely different behavior (guns,
// medical tools, ...) once Phase 3b/6 need it.
public partial class Item : WorldObject
{
    [Export] public string IconSheetPath = "";
    [Export] public string IconState = "";

    // Shared stat block (weight/stack/category/wear-slot/onmob states) -
    // the Resource half of the item identity split. May be null for
    // stat-less props; readers treat null as "default stats".
    [Export] public ItemData? Data { get; set; }

    public float Weight => Data?.Weight ?? 1.0f;

    private Sprite2D? _visual;
    private Node? _worldParent;

    public override void _Ready()
    {
        _visual = GetNodeOrNull<Sprite2D>("Visual");
        _worldParent = GetParent();

        if (_visual != null && IconSheetPath != "")
        {
            var sheet = DmiSheet.Load(IconSheetPath);
            _visual.Texture = sheet?.GetFrame(IconState);
        }

        RegisterAtCurrentPosition();
    }

    private void RegisterAtCurrentPosition()
    {
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        var cell = new Vector2I(
            Mathf.FloorToInt(Position.X / WorldGrid.DefaultCellSize),
            Mathf.FloorToInt(Position.Y / WorldGrid.DefaultCellSize));
        worldGrid.PlaceOccupant(this, cell);
    }

    // Puts the item back into the map at a world position - used when
    // dropped from an inventory. Reparents back to whatever node originally
    // owned it (the map scene) rather than wherever it's currently parented
    // (an inventory holder), so dropped items land in the right part of the
    // scene tree regardless of who's holding them.
    //
    // Every call site today only ever runs server-side (Do* handlers are
    // gated behind Multiplayer.IsServer() before they touch items at all -
    // see PlayerMob.DoDrop/DoPickup), so the mutation always applies locally
    // first; the broadcast just brings remote peers' independent copies of
    // this same node (same NodePath - see Item.tscn's deterministic scene
    // authoring/spawn-naming, no separate network-id scheme needed) up to
    // date. CallLocal=false on the Rpc since the direct call above already
    // covers the server's own copy, same convention as PlayerMob.SyncPosition.
    public void PlaceInWorld(Vector2 position)
    {
        DoPlaceInWorld(position);

        if (Multiplayer.HasMultiplayerPeer() && Multiplayer.IsServer())
        {
            Rpc(nameof(SyncPlaceInWorld), position);
        }
    }

    private void DoPlaceInWorld(Vector2 position)
    {
        if (GetParent() != _worldParent)
        {
            GetParent()?.RemoveChild(this);
            _worldParent?.AddChild(this);
        }

        Position = position;
        Visible = true;
        RegisterAtCurrentPosition();
        GD.Print($"[Item] {Name} placed in world at {position}");
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false)]
    private void SyncPlaceInWorld(Vector2 position) => DoPlaceInWorld(position);

    // Takes the item out of the map (picked up into an inventory) - caller
    // is responsible for reparenting it under the holder afterward. See
    // PlaceInWorld's comment above for the broadcast/authority reasoning.
    public void RemoveFromWorld()
    {
        DoRemoveFromWorld();

        if (Multiplayer.HasMultiplayerPeer() && Multiplayer.IsServer())
        {
            Rpc(nameof(SyncRemoveFromWorld));
        }
    }

    private void DoRemoveFromWorld()
    {
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        worldGrid.RemoveOccupant(this, GridCell);
        GetParent()?.RemoveChild(this);
        Visible = false;
        GD.Print($"[Item] {Name} removed from world");
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false)]
    private void SyncRemoveFromWorld() => DoRemoveFromWorld();

    // Late-join catch-up: a peer connecting mid-round only gets this item's
    // scene-authored default via the normal map-load broadcast (see
    // GameRoot.OnPeerConnected), which misses anything that's moved/been
    // picked up since. Server-only. Deliberately out of scope: an item
    // currently held in an inventory (not on the ground) isn't replayed here
    // at all - full inventory-state catch-up belongs to Phase 8 (Inventory
    // mechanics), not this networking-pattern pass. See PORT_ROADMAP.md.
    public void ReplayGroundStateTo(long peerId)
    {
        if (!Multiplayer.IsServer() || !Visible) return;
        RpcId(peerId, nameof(SyncPlaceInWorld), Position);
    }

    // Lands the item up to maxCells away in a straight line, stopping short
    // of the first dense cell it would enter. No arc/velocity simulation -
    // that's projectile territory (Phase 3b), this is just "toss it that way."
    public void ThrowInDirection(Vector2I fromCell, Vector2I direction, int maxCells)
    {
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        var landingCell = fromCell;

        for (var i = 1; i <= maxCells; i++)
        {
            var candidate = fromCell + direction * i;
            if (worldGrid.IsDense(candidate)) break;
            landingCell = candidate;
        }

        PlaceInWorld(new Vector2(
            landingCell.X * WorldGrid.DefaultCellSize + WorldGrid.DefaultCellSize / 2f,
            landingCell.Y * WorldGrid.DefaultCellSize + WorldGrid.DefaultCellSize / 2f));
    }
}
