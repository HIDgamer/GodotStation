using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using Godot;

namespace GodotStation.Core.Assets;

// Runtime slicer for the .png + .icon.json pairs Tools/dmi_convert.py
// produces from ucfss13's DMI icon sheets (see that script's header comment
// for why converting the format itself isn't a copyright concern). Callers
// never touch the JSON directly - load a sheet once, ask for frames by
// (state, direction) after that.
public sealed class DmiSheet
{
    // DMI delay values are in BYOND "ticks" - deciseconds by convention
    // (world.tick_lag default 1 == 0.1s). Kept as its own constant rather
    // than folded into the converter so the unit assumption is visible here,
    // next to where it's actually applied.
    private const float SecondsPerTick = 0.1f;

    private sealed class SheetData
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int Columns { get; set; }
        public Dictionary<string, StateData> States { get; set; } = new();
    }

    private sealed class StateData
    {
        public int Dirs { get; set; }
        public int Frames { get; set; }
        public float[] Delay { get; set; } = System.Array.Empty<float>();
        public bool Movement { get; set; }
        public bool Rewind { get; set; }
        public int Loop { get; set; }
        public Dictionary<string, int[][]> FramesByDir { get; set; } = new();
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly Texture2D _texture;
    private readonly SheetData _data;
    private readonly Dictionary<(string state, string dir, int frame), AtlasTexture> _cache = new();

    private DmiSheet(Texture2D texture, SheetData data)
    {
        _texture = texture;
        _data = data;
    }

    // pngPath is the sheet's res:// path, e.g.
    // "res://Icons/mob/humans/human.png" - the sidecar JSON is
    // expected alongside it as "human.icon.json", matching the converter's
    // output naming.
    public static DmiSheet? Load(string pngPath)
    {
        var texture = GD.Load<Texture2D>(pngPath);
        if (texture == null)
        {
            GD.PrintErr($"[DmiSheet] Failed to load texture at {pngPath}.");
            return null;
        }

        var jsonPath = pngPath.GetBaseName() + ".icon.json";
        using var file = FileAccess.Open(jsonPath, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PrintErr($"[DmiSheet] Failed to open sidecar metadata at {jsonPath}: {FileAccess.GetOpenError()}.");
            return null;
        }

        SheetData? data;
        try
        {
            data = JsonSerializer.Deserialize<SheetData>(file.GetAsText(), JsonOptions);
        }
        catch (JsonException e)
        {
            GD.PrintErr($"[DmiSheet] Failed to parse {jsonPath}: {e.Message}");
            return null;
        }

        if (data == null) return null;
        return new DmiSheet(texture, data);
    }

    public bool HasState(string state) => _data.States.ContainsKey(state);

    public float[] GetDelaySeconds(string state)
    {
        if (!_data.States.TryGetValue(state, out var st) || st.Delay.Length == 0) return new[] { SecondsPerTick };

        var seconds = new float[st.Delay.Length];
        for (var i = 0; i < st.Delay.Length; i++) seconds[i] = st.Delay[i] * SecondsPerTick;
        return seconds;
    }

    // Falls back to "south" if the requested direction doesn't exist for
    // this state (e.g. a dirs=1 state asked for "north") - every DMI state
    // has at least a south frame, so this never fails outright unless the
    // state name itself is wrong.
    public Texture2D? GetFrame(string state, string direction = "south", int frameIndex = 0)
    {
        if (!_data.States.TryGetValue(state, out var st))
        {
            GD.PrintErr($"[DmiSheet] Unknown state '{state}'.");
            return null;
        }

        if (!st.FramesByDir.TryGetValue(direction, out var cells) && !st.FramesByDir.TryGetValue("south", out cells))
        {
            return null;
        }

        if (cells.Length == 0) return null;
        frameIndex = Mathf.Clamp(frameIndex, 0, cells.Length - 1);

        var key = (state, direction, frameIndex);
        if (_cache.TryGetValue(key, out var cached)) return cached;

        var cell = cells[frameIndex];
        var atlas = new AtlasTexture
        {
            Atlas = _texture,
            Region = new Rect2(cell[0] * _data.Width, cell[1] * _data.Height, _data.Width, _data.Height),
        };

        _cache[key] = atlas;
        return atlas;
    }

    public int GetFrameCount(string state)
        => _data.States.TryGetValue(state, out var st) ? st.Frames : 0;

    // Raw sheet accessors for consumers that need to build their own atlas
    // (TileSetAtlasSource for TurfTileMap) rather than get a pre-sliced
    // AtlasTexture back - same sidecar data GetFrame already parses.
    public Texture2D SheetTexture => _texture;
    public Vector2I CellSize => new(_data.Width, _data.Height);

    public bool TryGetAtlasCell(string state, string direction, int frameIndex, out Vector2I atlasCell)
    {
        atlasCell = default;
        if (!_data.States.TryGetValue(state, out var st)) return false;
        if (!st.FramesByDir.TryGetValue(direction, out var cells) && !st.FramesByDir.TryGetValue("south", out cells)) return false;
        if (cells.Length == 0) return false;

        frameIndex = Mathf.Clamp(frameIndex, 0, cells.Length - 1);
        var cell = cells[frameIndex];
        atlasCell = new Vector2I(cell[0], cell[1]);
        return true;
    }
}
