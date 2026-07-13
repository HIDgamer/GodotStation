using System.Collections.Generic;
using Godot;

namespace GodotStation.Core.Assets;

// GDScript can't instantiate/call a plain C# class like DmiSheet directly -
// it needs a Node it can reach through the object system. This autoload is
// that seam: any GDScript UI (the HUD, future inventory screens, ...) asks
// for a frame by sheet path/state and gets a cached Texture2D back, without
// needing to know DmiSheet exists.
public partial class IconBridge : Node
{
    private readonly Dictionary<string, DmiSheet> _sheets = new();

    // No-default overload - GDScript calling a C# method with default
    // parameter values omitted can fail to resolve the bind on some Godot
    // Mono versions ("Nonexistent function"), so the entry point GDScript
    // actually calls (2 args) is explicit rather than relying on optional args.
    public Texture2D? GetFrame(string sheetPath, string state) => GetFrame(sheetPath, state, "south", 0);

    public Texture2D? GetFrame(string sheetPath, string state, string direction, int frameIndex)
    {
        if (!_sheets.TryGetValue(sheetPath, out var sheet))
        {
            var loaded = DmiSheet.Load(sheetPath);
            if (loaded == null) return null;
            sheet = loaded;
            _sheets[sheetPath] = sheet;
        }

        return sheet.GetFrame(state, direction, frameIndex);
    }
}
