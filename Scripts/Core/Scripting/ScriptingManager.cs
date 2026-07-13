using Godot;
using Godot.Collections;

namespace GodotStation.Core.Scripting;

// The sole bridge to the sandboxed Lua scripting layer (godot-sandbox +
// gamemaker_lua.elf, built in M1 - see sandbox-programs/gamemaker-lua). Owns
// the one Sandbox node, loads a deployed script from user://gamemaker_scripts
// if present, and exposes CallHook() for other systems to fan out signals
// into Lua.
//
// Signal-first by design: gameplay code should never reach into
// ScriptingManager from deep inside a subsystem. A subsystem raises its own
// ordinary C#/Godot signal; whatever wires those signals to CallHook() calls
// (this class, or a thin adapter next to it) is the only thing that needs to
// know Lua exists at all. Core gameplay never depends on Lua being present -
// every method here is safe to call (and safely no-ops) even if the sandbox
// failed to load.
public partial class ScriptingManager : Node
{
    private const string ScriptDeployPath = "user://gamemaker_scripts/main.lua";

    // uid:// rather than res://path - survives the file being moved/renamed,
    // and is the export-safe way to reference a project asset. Read from
    // Addons/godot-sandbox-scripts/gamemaker_lua.elf.uid; regenerate this
    // constant from that sidecar file if the .elf is ever rebuilt/replaced.
    private const string SandboxProgramUid = "uid://cfkq4x7m03ywv";

    private Node? _sandbox;
    private bool _active;

    public override void _Ready()
    {
        if (!ResourceLoader.Exists(SandboxProgramUid))
        {
            GD.PrintErr($"[ScriptingManager] Sandbox program not found: {SandboxProgramUid}");
            return;
        }

        var elfScript = GD.Load<Script>(SandboxProgramUid);
        if (elfScript == null)
        {
            GD.PrintErr($"[ScriptingManager] Failed to load sandbox program: {SandboxProgramUid}");
            return;
        }

        _sandbox = new Node { Name = "GamemakerLuaSandbox" };
        _sandbox.SetScript(elfScript);
        AddChild(_sandbox);
        _active = true;

        LoadDeployedScript();
    }

    // Re-reads and re-runs the deployed script without restarting the game -
    // the actual point of this whole layer. Callers are responsible for
    // gating this to trusted roles once a privilege system exists.
    public void ReloadScripts()
    {
        if (!_active || _sandbox == null) return;
        _sandbox.Call("reset_globals");
        LoadDeployedScript();
    }

    private void LoadDeployedScript()
    {
        if (_sandbox == null) return;

        if (!FileAccess.FileExists(ScriptDeployPath))
        {
            GD.Print($"[ScriptingManager] No script deployed at {ScriptDeployPath}; running with no hooks.");
            return;
        }

        using var file = FileAccess.Open(ScriptDeployPath, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PrintErr($"[ScriptingManager] Failed to open {ScriptDeployPath}: {FileAccess.GetOpenError()}");
            return;
        }

        _sandbox.Call("run", file.GetAsText());
        GD.Print("[ScriptingManager] Loaded gamemaker script.");
    }

    // Calls a global Lua function by name if the deployed script defined it;
    // silently does nothing otherwise (or if the sandbox never loaded) - so
    // callers can fire hooks unconditionally without checking IsActive first.
    public void CallHook(string name, params Variant[] args)
    {
        if (!_active || _sandbox == null) return;

        var array = new Array();
        foreach (var arg in args) array.Add(arg);

        _sandbox.Call("call_hook", name, array);
    }

    // Exposes a C# callback as a Lua-callable global function. Keep this
    // set small and explicit - it IS the sandbox boundary (see main.cpp's
    // own header comment): a Lua script can only reach what's registered here.
    public void AddFunction(string luaFunctionName, Callable callback)
    {
        if (!_active || _sandbox == null) return;
        _sandbox.Call("add_function", luaFunctionName, callback);
    }

    public bool IsActive => _active;
}
