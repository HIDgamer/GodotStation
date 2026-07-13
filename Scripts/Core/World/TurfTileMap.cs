using System.Collections.Generic;
using Godot;
using GodotStation.Core.Assets;
using GodotStation.Core.Atoms;

namespace GodotStation.Core.World;

// Renders WorldGrid's turfs through a real Godot TileMapLayer + TileSet
// Terrain setup (ucfss13's open turfs pick among neighbor-aware autotile icon_state
// families at runtime via update_icon() - Godot's Terrain system is the
// engine-native equivalent, studied as design reference only, never
// ported). Each distinct (sheet, state) turf identity gets its own terrain
// set with the source DMI cell registered as a tile - map-authored and
// future DMM-loaded turfs both render through SetCellTurf, so there's one
// live path instead of a bootstrap script hardcoding sprites per cell.
//
// Terrain metadata (TerrainSet/Terrain) is wired on every tile so this is
// a real terrain-aware TileSet, ready for authored corner/edge tile
// variants later. Placement itself uses direct SetCell rather than
// SetCellsTerrainConnect for now - with exactly one tile per terrain
// there's nothing for the connect solver to choose between yet; wiring up
// corner-matching needs someone to reverse-engineer each floor/wall
// family's update_icon() bitmask semantics and author the peering-bit
// tile variants, which is future map-tooling work, not this pass.
public partial class TurfTileMap : TileMapLayer
{
    private readonly Dictionary<string, DmiSheet> _sheets = new();
    private readonly Dictionary<string, int> _sourceIds = new();
    private readonly Dictionary<string, (int sourceId, Vector2I atlasCell)> _registered = new();

    public override void _Ready()
    {
        TileSet = new TileSet
        {
            TileSize = new Vector2I((int)WorldGrid.DefaultCellSize, (int)WorldGrid.DefaultCellSize),
        };
    }

    public void SetCellTurf(Vector2I cell, Turf turf)
    {
        if (turf.IconSheetPath == "" || turf.IconState == "")
        {
            SetCell(cell);
            return;
        }

        var key = Register(turf.IconSheetPath, turf.IconState);
        if (key == null)
        {
            SetCell(cell);
            return;
        }

        var (sourceId, atlasCell) = _registered[key];
        SetCell(cell, sourceId, atlasCell);
    }

    public void ClearCell(Vector2I cell) => SetCell(cell);

    // Ensures a (sheet, state) turf identity has a TileSetAtlasSource tile
    // and a dedicated terrain set, caching the result. Returns the cache
    // key, or null if the sheet/state couldn't be loaded/found.
    private string? Register(string sheetPath, string state)
    {
        var key = sheetPath + "|" + state;
        if (_registered.ContainsKey(key)) return key;

        if (!_sheets.TryGetValue(sheetPath, out var sheet))
        {
            var loaded = DmiSheet.Load(sheetPath);
            if (loaded == null) return null;
            sheet = loaded;
            _sheets[sheetPath] = sheet;
        }

        if (!sheet.TryGetAtlasCell(state, "south", 0, out var atlasCell)) return null;

        if (!_sourceIds.TryGetValue(sheetPath, out var sourceId))
        {
            var source = new TileSetAtlasSource
            {
                Texture = sheet.SheetTexture,
                TextureRegionSize = sheet.CellSize,
            };
            sourceId = TileSet.AddSource(source);
            _sourceIds[sheetPath] = sourceId;
        }

        var atlasSource = (TileSetAtlasSource)TileSet.GetSource(sourceId);
        if (!atlasSource.HasTile(atlasCell))
        {
            atlasSource.CreateTile(atlasCell);
        }

        var terrainSet = TileSet.GetTerrainSetsCount();
        TileSet.AddTerrainSet();
        TileSet.SetTerrainSetMode(terrainSet, TileSet.TerrainMode.CornersAndSides);
        TileSet.AddTerrain(terrainSet);
        TileSet.SetTerrainName(terrainSet, 0, state);

        var tileData = atlasSource.GetTileData(atlasCell, 0);
        tileData.TerrainSet = terrainSet;
        tileData.Terrain = 0;

        _registered[key] = (sourceId, atlasCell);
        return key;
    }
}
