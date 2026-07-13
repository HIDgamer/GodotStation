using System.Collections.Generic;
using Godot;
using GodotStation.Core.Assets;

namespace GodotStation.Game.Mobs;

// Layered directional mob renderer - the DMI-pipeline REWRITE of the old
// prototype's SpriteSystem (old asset paths are gone; layer stacking is the
// same idea, the art source is ucfss13's converted onmob DMI sheets via
// DmiSheet/IconBridge). Body is a whole-body state for now; per-body-part
// assembly (ethnicity/gender variants from species sheets) is Phase 5 depth.
//
// Purely visual and client-side driven: PlayerMob tells it what to show
// (facing, layer states, prone, tint) - it holds no game state and makes no
// gameplay decisions.
public partial class MobAppearance : Node2D, IMobComponent
{
    // Draw order, bottom to top. Slot names match Inventory's equipment
    // slots where applicable so equip events map 1:1 onto layers.
    public static readonly string[] LayerOrder =
    {
        "body", "uniform", "shoes", "gloves", "jacket", "back",
        "mask", "eyes", "head", "inhand_left", "inhand_right",
    };

    private static readonly string[] FacingNames = { "south", "north", "east", "west" };

    private readonly Dictionary<string, Sprite2D> _layers = new();
    private readonly Dictionary<string, (string sheet, string state)> _layerSources = new();
    private int _facingIndex;

    public void Initialize(Mob mob) { }
    public void Cleanup() { }

    public override void _Ready()
    {
        for (var i = 0; i < LayerOrder.Length; i++)
        {
            var sprite = new Sprite2D
            {
                Name = LayerOrder[i],
                ZIndex = i,
                TextureFilter = TextureFilterEnum.Nearest,
                Visible = false,
            };
            _layers[LayerOrder[i]] = sprite;
            AddChild(sprite);
        }
    }

    public void SetLayer(string layer, string sheetPath, string state)
    {
        if (!_layers.TryGetValue(layer, out var sprite)) return;

        if (sheetPath == "" || state == "")
        {
            ClearLayer(layer);
            return;
        }

        _layerSources[layer] = (sheetPath, state);
        ApplyLayerTexture(layer, sprite);
        sprite.Visible = true;
    }

    public void ClearLayer(string layer)
    {
        if (!_layers.TryGetValue(layer, out var sprite)) return;
        _layerSources.Remove(layer);
        sprite.Visible = false;
        sprite.Texture = null;
    }

    public void SetFacing(int facingIndex)
    {
        if (facingIndex == _facingIndex) return;
        _facingIndex = Mathf.Clamp(facingIndex, 0, FacingNames.Length - 1);

        foreach (var (layer, sprite) in _layers)
        {
            if (sprite.Visible) ApplyLayerTexture(layer, sprite);
        }
    }

    // Placeholder prone visual (rotate the whole stack) until real lying
    // sprites/directional prone states are wired in Phase 5.
    public void SetProne(bool isProne) => RotationDegrees = isProne ? 90f : 0f;

    public void SetTint(Color tint) => Modulate = tint;

    private void ApplyLayerTexture(string layer, Sprite2D sprite)
    {
        if (!_layerSources.TryGetValue(layer, out var source)) return;

        var bridge = GetNodeOrNull<IconBridge>("/root/IconBridge");
        var texture = bridge?.GetFrame(source.sheet, source.state, FacingNames[_facingIndex], 0);

        // A state missing the requested facing falls back inside DmiSheet;
        // a fully failed lookup hides the layer rather than leaving a stale
        // texture from the previous state.
        sprite.Texture = texture;
        sprite.Visible = texture != null;
    }
}
