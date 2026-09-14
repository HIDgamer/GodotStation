using System.Collections.Generic;
using Godot;
using GodotStation.Core.Atoms;
using GodotStation.Core.World;
using GodotStation.Game.World.Turfs;

namespace GodotStation.Game.World;

// Builds an original, small, hand-scoped test room directly in code rather
// than from a ucfss13-derived .dmm layout (see the M2 roadmap's copyright
// workflow - map geography is inspired by "a room with a border," not traced
// from any specific source map). Visuals are entirely WorldGrid's problem
// now (SetTurf pushes to its TurfTileMap) - this class only decides which
// turf type goes where.
public partial class MapBootstrap : Node2D
{
    [Export] public int RoomWidth = 16;
    [Export] public int RoomHeight = 10;

    // A gap left in the south wall for TestMap.tscn's Door instance to sit
    // in - without this the border loop below would wall it back in, and
    // Phase 3's new Door/bump-to-open behavior would have nothing real to
    // exercise (see PORT_ROADMAP.md's Doors/airlocks entry).
    private static readonly Vector2I DoorwayCell = new(8, 9);

    private readonly List<SpawnPoint> _spawnPoints = new();
    private int _nextSpawnIndex;

    public override void _Ready()
    {
        foreach (var child in GetChildren())
        {
            if (child is SpawnPoint spawnPoint) _spawnPoints.Add(spawnPoint);
        }

        BuildRoom();
    }

    public Vector2 GetNextSpawnWorldPosition()
    {
        if (_spawnPoints.Count == 0) return Vector2.Zero;

        var point = _spawnPoints[_nextSpawnIndex % _spawnPoints.Count];
        _nextSpawnIndex++;
        return point.Position;
    }

    private void BuildRoom()
    {
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");

        for (var x = 0; x < RoomWidth; x++)
        {
            for (var y = 0; y < RoomHeight; y++)
            {
                var cell = new Vector2I(x, y);
                var isBorder = x == 0 || y == 0 || x == RoomWidth - 1 || y == RoomHeight - 1;
                Turf turf = isBorder && cell != DoorwayCell ? new WallTurf() : new FloorTurf();

                worldGrid.SetTurf(cell, turf);
            }
        }
    }
}
