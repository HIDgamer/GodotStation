using Godot;
using System;
using System.Collections.Generic;

public partial class ServerConfig : Node
{
    private const string DefaultServerName = "USCMGS";
    private const int DefaultPort = 2088;
    private const int DefaultMaxPlayers = 64;
    private const string DefaultMap = "DDome";
    private const string DefaultGamemode = "PVE";
    private const string DefaultBackendUrl = "https://auth.godostation.com";
    private const bool DefaultIsPublic = true;

    private const string ConfigFilePath = "user://server_config.cfg";

    private readonly Dictionary<string, string> _dotEnv = new(StringComparer.OrdinalIgnoreCase);
    private bool _loaded;

    public string ServerName  { get; private set; } = DefaultServerName;
    public int Port           { get; private set; } = DefaultPort;
    public int MaxPlayers     { get; private set; } = DefaultMaxPlayers;
    public string Map         { get; private set; } = DefaultMap;
    public string Gamemode    { get; private set; } = DefaultGamemode;
    public string BackendUrl  { get; private set; } = DefaultBackendUrl;
    public string ServerToken { get; private set; } = "";
    public string Password    { get; private set; } = "";
    public bool IsPublic      { get; private set; } = DefaultIsPublic;
    public string Description { get; private set; } = "";

    public override void _Ready() => Reload();

    public void EnsureLoaded()
    {
        if (!_loaded)
            Reload();
    }

    public void Reload()
    {
        ResetDefaults();
        LoadDotEnvFiles();

        if (Godot.FileAccess.FileExists(ConfigFilePath))
            LoadFromFile(ConfigFilePath);

        // Deployment overrides should win over persisted user config.
        LoadFromEnvironment();
        BackendUrl = NormalizeBackendUrl(BackendUrl);

        _loaded = true;

        GD.Print(
            $"[ServerConfig] Name={ServerName} Port={Port} MaxPlayers={MaxPlayers} Map={Map} " +
            $"Gamemode={Gamemode} Public={IsPublic} TokenSet={!string.IsNullOrEmpty(ServerToken)}");
    }

    private void ResetDefaults()
    {
        ServerName = DefaultServerName;
        Port = DefaultPort;
        MaxPlayers = DefaultMaxPlayers;
        Map = DefaultMap;
        Gamemode = DefaultGamemode;
        BackendUrl = DefaultBackendUrl;
        ServerToken = "";
        Password = "";
        IsPublic = DefaultIsPublic;
        Description = "";
    }

    private void LoadFromEnvironment()
    {
        ServerName = EnvAny(new[] { "SERVER_NAME" }, ServerName);
        Port = EnvIntAny(new[] { "SERVER_PORT", "PORT" }, Port);
        MaxPlayers = EnvIntAny(new[] { "MAX_PLAYERS", "SERVER_MAX_PLAYERS" }, MaxPlayers);
        Map = EnvAny(new[] { "SERVER_MAP", "MAP" }, Map);
        Gamemode = EnvAny(new[] { "SERVER_GAMEMODE", "GAMEMODE", "GAME_MODE" }, Gamemode);
        BackendUrl = EnvAny(new[] { "BACKEND_URL", "API_URL", "LOBBY_API_URL" }, BackendUrl);
        ServerToken = EnvAny(new[] { "SERVER_TOKEN", "SERVER_API_KEY" }, ServerToken);
        Password = EnvAny(new[] { "SERVER_PASSWORD" }, Password);
        Description = EnvAny(new[] { "SERVER_DESCRIPTION" }, Description);
        IsPublic = EnvBoolAny(new[] { "SERVER_PUBLIC" }, IsPublic);
    }

    private void LoadDotEnvFiles()
    {
        _dotEnv.Clear();
        TryLoadDotEnv(".env");
        TryLoadDotEnv(".env.local");
    }

    private void TryLoadDotEnv(string path)
    {
        if (!System.IO.File.Exists(path))
            return;

        try
        {
            var lines = System.IO.File.ReadAllLines(path);
            foreach (var rawLine in lines)
            {
                var line = rawLine.Trim();
                if (string.IsNullOrEmpty(line) || line.StartsWith("#"))
                    continue;

                var idx = line.IndexOf('=');
                if (idx <= 0)
                    continue;

                var key = line[..idx].Trim();
                var value = line[(idx + 1)..].Trim();

                if (value.Length >= 2 &&
                    ((value[0] == '"' && value[^1] == '"') || (value[0] == '\'' && value[^1] == '\'')))
                {
                    value = value[1..^1];
                }

                if (!string.IsNullOrEmpty(key))
                    _dotEnv[key] = value;
            }
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerConfig] Failed to parse {path}: {e.Message}");
        }
    }

    private void LoadFromFile(string path)
    {
        var cfg = new ConfigFile();
        if (cfg.Load(path) != Error.Ok)
            return;

        ServerName = (string)cfg.GetValue("server", "name", ServerName);
        Port = (int)cfg.GetValue("server", "port", Port);
        MaxPlayers = (int)cfg.GetValue("server", "max_players", MaxPlayers);
        Map = (string)cfg.GetValue("server", "map", Map);
        Gamemode = (string)cfg.GetValue("server", "gamemode", Gamemode);
        BackendUrl = (string)cfg.GetValue("server", "backend_url", BackendUrl);
        ServerToken = (string)cfg.GetValue("server", "token", ServerToken);
        Password = (string)cfg.GetValue("server", "password", Password);
        Description = (string)cfg.GetValue("server", "description", Description);
        IsPublic = (bool)cfg.GetValue("server", "public", IsPublic);

        GD.Print("[ServerConfig] Loaded overrides from server_config.cfg");
    }

    private string Env(string key, string fallback)
    {
        var v = System.Environment.GetEnvironmentVariable(key);
        if (!string.IsNullOrEmpty(v))
            return v;

        return _dotEnv.TryGetValue(key, out var dotEnvValue) && !string.IsNullOrEmpty(dotEnvValue)
            ? dotEnvValue
            : fallback;
    }

    private string EnvAny(IEnumerable<string> keys, string fallback)
    {
        foreach (var key in keys)
        {
            var value = Env(key, "");
            if (!string.IsNullOrEmpty(value))
                return value;
        }
        return fallback;
    }

    private int EnvIntAny(IEnumerable<string> keys, int fallback)
    {
        foreach (var key in keys)
        {
            var value = Env(key, "");
            if (int.TryParse(value, out var parsed))
                return parsed;
        }
        return fallback;
    }

    private bool EnvBoolAny(IEnumerable<string> keys, bool fallback)
    {
        foreach (var key in keys)
        {
            var value = Env(key, "");
            if (string.IsNullOrEmpty(value))
                continue;

            switch (value.Trim().ToLowerInvariant())
            {
                case "1":
                case "true":
                case "yes":
                case "on":
                    return true;
                case "0":
                case "false":
                case "no":
                case "off":
                    return false;
            }
        }

        return fallback;
    }

    private static string NormalizeBackendUrl(string rawUrl)
    {
        var url = string.IsNullOrWhiteSpace(rawUrl) ? DefaultBackendUrl : rawUrl.Trim();
        url = url.TrimEnd('/');

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            return DefaultBackendUrl;

        if (string.Equals(uri.Host, "godotstation.duckdns.org", StringComparison.OrdinalIgnoreCase))
            return DefaultBackendUrl;

        return url;
    }
}
