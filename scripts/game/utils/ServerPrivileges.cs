using Godot;
using System;
using System.Collections.Generic;
using System.IO;

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
    private string _privilegesPath = "";

    public override void _Ready()
    {
        if (!ShouldRunInThisRuntime())
        {
            SetProcess(false);
            return;
        }

        _privilegesPath = Path.Combine(System.Environment.CurrentDirectory, "privileges.json");

	        // Allow path override via environment variable.
	        var envPath = System.Environment.GetEnvironmentVariable("PRIVILEGES_PATH");
	        if (!string.IsNullOrEmpty(envPath))
	            _privilegesPath = envPath;

	        _privilegesPath = NormalizePrivilegesPath(_privilegesPath);

	        Load();
	    }

    // Public API.

    public ServerRole GetRole(string discordTag)
    {
        if (string.IsNullOrEmpty(discordTag))
            return ServerRole.None;

        if (TryGetRole(discordTag, out var role))
            return role;

        var hashIndex = discordTag.IndexOf('#');
        if (hashIndex > 0 && TryGetRole(discordTag[..hashIndex], out role))
            return role;

        return ServerRole.None;
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

        if (!Godot.FileAccess.FileExists(_privilegesPath) &&
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
            if (Godot.FileAccess.FileExists(_privilegesPath))
            {
                using var fa = Godot.FileAccess.Open(_privilegesPath, Godot.FileAccess.ModeFlags.Read);
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
                GD.Print($"  {kv.Key} -> {kv.Value}");
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

            RegisterRoleAlias(tag, role);

            var hashIndex = tag.IndexOf('#');
            if (hashIndex > 0)
                RegisterRoleAlias(tag[..hashIndex], role);
        }
    }

    private bool TryGetRole(string key, out ServerRole role)
    {
        var normalized = key.Trim();
        return _roles.TryGetValue(normalized, out role);
    }

    private void RegisterRoleAlias(string key, ServerRole role)
    {
        var normalized = key.Trim();
        if (string.IsNullOrEmpty(normalized))
            return;

        // Higher roles win if an identity appears in multiple categories.
        if (!_roles.TryGetValue(normalized, out var existing) || existing < role)
            _roles[normalized] = role;
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
            var dir = Path.GetDirectoryName(_privilegesPath);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);
            System.IO.File.WriteAllText(_privilegesPath, template);
            GD.Print($"[ServerPrivileges] Wrote default template to {_privilegesPath}");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerPrivileges] Could not write default file: {e.Message}");
        }
    }

	    private static bool ShouldRunInThisRuntime()
	    {
	        if (OS.HasFeature("dedicated_server"))
	            return true;

	        if (string.Equals(DisplayServer.GetName(), "headless", StringComparison.OrdinalIgnoreCase))
	            return true;

	        var args = OS.GetCmdlineArgs();
	        for (int i = 0; i < args.Length; i++)
	            if (args[i] == "--headless")
	                return true;

	        return false;
	    }

	    private static string NormalizePrivilegesPath(string path)
	    {
	        if (string.IsNullOrWhiteSpace(path))
	            return path;

	        var normalized = path.Trim();
	        if (!string.Equals(OS.GetName(), "Windows", StringComparison.OrdinalIgnoreCase))
	        {
	            normalized = normalized.Replace('\\', '/');
	            if (normalized.Length >= 3 &&
	                char.IsLetter(normalized[0]) &&
	                normalized[1] == ':' &&
	                normalized[2] == '/')
	            {
	                normalized = normalized[2..];
	            }
	        }

	        return normalized;
	    }
}
