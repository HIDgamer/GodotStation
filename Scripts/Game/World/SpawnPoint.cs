using Godot;

namespace GodotStation.Game.World;

// Marker placed in a map scene. MapBootstrap collects every SpawnPoint under
// the map root and hands them out round-robin as players join - kept as a
// tiny typed node rather than a bare Marker2D + group string so spawn logic
// gets compile-time safety instead of matching on a magic group name.
public partial class SpawnPoint : Node2D
{
}
