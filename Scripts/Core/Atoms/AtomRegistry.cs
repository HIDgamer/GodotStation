using System.Collections.Generic;
using Godot;

namespace GodotStation.Core.Atoms;

// Stable type-id -> PackedScene lookup, since Godot has no typepath-to-
// instance mechanism as convenient as DM's `new /obj/.../m41a()`. Content
// phases register their scenes here (directly or via RegisterFromPath) and
// spawn by id rather than holding scene references everywhere.
public partial class AtomRegistry : Node
{
    private readonly Dictionary<string, PackedScene> _scenes = new();

    public void Register(string typeId, PackedScene scene)
    {
        if (_scenes.ContainsKey(typeId))
        {
            GD.PrintErr($"[AtomRegistry] '{typeId}' is already registered - overwriting.");
        }
        _scenes[typeId] = scene;
    }

    // Pass a uid:// reference, not a res://path, wherever possible - it
    // survives the resource being moved/renamed and is the export-safe way
    // to reference a project asset (Godot writes a .uid sidecar next to
    // every imported resource; read that file for the identifier).
    public void RegisterFromPath(string typeId, string resourcePath)
    {
        var scene = GD.Load<PackedScene>(resourcePath);
        if (scene == null)
        {
            GD.PrintErr($"[AtomRegistry] Failed to load scene at '{resourcePath}' for type id '{typeId}'.");
            return;
        }
        Register(typeId, scene);
    }

    public bool IsRegistered(string typeId) => _scenes.ContainsKey(typeId);

    public Node? Spawn(string typeId)
    {
        if (!_scenes.TryGetValue(typeId, out var scene))
        {
            GD.PrintErr($"[AtomRegistry] No scene registered for type id '{typeId}'.");
            return null;
        }
        return scene.Instantiate();
    }

    public T? Spawn<T>(string typeId) where T : class
    {
        var node = Spawn(typeId);
        if (node == null) return null;
        if (node is T typed) return typed;

        GD.PrintErr($"[AtomRegistry] Spawned '{typeId}' but it isn't a {typeof(T).Name} (got {node.GetType().Name}).");
        node.QueueFree();
        return null;
    }
}
