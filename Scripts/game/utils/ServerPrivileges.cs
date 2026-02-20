using Godot;
using System;
using System.Collections.Generic;

public partial class ServerPrivileges : Node
{
    public enum ServerRole
    {
        None          = 0,
        Moderator     = 1,
        Administrator = 2,
        Host          = 3,
        Owner         = 4,
    }

    private readonly Dictionary<string, ServerRole> _roles = new(StringComparer.OrdinalIgnoreCase);
    private string _privilegesPath = "/home/ubuntu/godotstation/privileges.json";

    public override void _Ready()
    {
        // Allow path override via environment variable.
        var envPath = System.Environment.GetEnvironmentVariable("PRIVILEGES_PATH");
        if (!string.IsNullOrEmpty(envPath))
            _privilegesPath = envPath;

        // Only relevant on dedicated server - bail out quietly on clients.
        var config = GetNodeOrNull<ServerConfig>("/root/ServerConfig");
        if (config == null)
        {
            SetProcess(false);
            return;
        }

        Load();
    }

    // Public API.

    public ServerRole GetRole(string discordTag)
    {
        if (string.IsNullOrEmpty(discordTag)) return ServerRole.None;
        return _roles.TryGetValue(discordTag.Trim(), out var role) ? role : ServerRole.None;
    }

    public bool IsOwnerOrHost(string discordTag)
        => GetRole(discordTag) >= ServerRole.Host;

    public bool CanStartGame(string discordTag)
        => GetRole(discordTag) >= ServerRole.Administrator;

    public bool CanDelayGame(string discordTag)
        => GetRole(discordTag) >= ServerRole.Administrator;

    public bool CanKick(string discordTag)
        => GetRole(discordTag) >= ServerRole.Moderator;

    public bool IsStaff(string discordTag)
        => GetRole(discordTag) != ServerRole.None;

    // Loading.

    public void Load()
    {
        _roles.Clear();

        if (!FileAccess.FileExists(_privilegesPath) &&
            !System.IO.File.Exists(_privilegesPath))
        {
            GD.PrintErr($"[ServerPrivileges] File not found: {_privilegesPath}");
            GD.PrintErr($"[ServerPrivileges] Create it to assign staff roles. Running with no privileged users.");
            WriteDefaultFile();
            return;
        }

        try
        {
            string raw;
            // Try Godot virtual FS first, fall back to system IO.
            if (FileAccess.FileExists(_privilegesPath))
            {
                using var fa = FileAccess.Open(_privilegesPath, FileAccess.ModeFlags.Read);
                raw = fa.GetAsText();
            }
            else
            {
                raw = System.IO.File.ReadAllText(_privilegesPath);
            }

            var parser = new Json();
            if (parser.Parse(raw) != Error.Ok)
            {
                GD.PrintErr($"[ServerPrivileges] JSON parse error in {_privilegesPath}");
                return;
            }

            var root = parser.Data.AsGodotDictionary();
            ParseRoleList(root, "owner",         ServerRole.Owner);
            ParseRoleList(root, "host",           ServerRole.Host);
            ParseRoleList(root, "administrator",  ServerRole.Administrator);
            ParseRoleList(root, "moderator",      ServerRole.Moderator);

            GD.Print($"[ServerPrivileges] Loaded {_roles.Count} privileged user(s) from {_privilegesPath}");
            foreach (var kv in _roles)
                GD.Print($"  {kv.Key} → {kv.Value}");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerPrivileges] Failed to load: {e.Message}");
        }
    }

    public void Reload() => Load();

    // Helpers.

    private void ParseRoleList(Godot.Collections.Dictionary root, string key, ServerRole role)
    {
        if (!root.ContainsKey(key)) return;
        var arr = root[key].AsGodotArray();
        foreach (var item in arr)
        {
            var tag = item.ToString().Trim();
            if (string.IsNullOrEmpty(tag)) continue;
            // Higher roles win if a tag is listed in multiple categories.
            if (!_roles.TryGetValue(tag, out var existing) || existing < role)
                _roles[tag] = role;
        }
    }

    private void WriteDefaultFile()
    {
        const string template = @"{
  ""owner"":         [],
  ""host"":          [],
  ""administrator"": [],
  ""moderator"":     []
}
";
        try
        {
            System.IO.File.WriteAllText(_privilegesPath, template);
            GD.Print($"[ServerPrivileges] Wrote default template to {_privilegesPath}");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerPrivileges] Could not write default file: {e.Message}");
        }
    }
}
