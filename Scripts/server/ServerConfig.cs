using Godot;

public partial class ServerConfig : Node
{
    public string ServerName     { get; private set; } = "USCMGS";
    public int    Port           { get; private set; } = 2088;
    public int    MaxPlayers     { get; private set; } = 64;
    public string Map            { get; private set; } = "DDome";
    public string Gamemode       { get; private set; } = "PVE";
    public string BackendUrl     { get; private set; } = "https://godotstation.duckdns.org";
    public string ServerToken    { get; private set; } = "";
    public string Password       { get; private set; } = "";
    public bool   IsPublic       { get; private set; } = true;
    public string Description    { get; private set; } = "";

    private const string ConfigFilePath = "user://server_config.cfg";

    public ServerConfig()
    {
        LoadFromEnvironment();
    }

    public override void _Ready()
    {
        if (FileAccess.FileExists(ConfigFilePath))
            LoadFromFile(ConfigFilePath);

        GD.Print($"[ServerConfig] Name={ServerName} Port={Port} MaxPlayers={MaxPlayers} Map={Map} Gamemode={Gamemode} Public={IsPublic}");
    }

private void LoadFromEnvironment()
{
    ServerName  = Env("SERVER_NAME",      ServerName); 
    Port        = EnvInt("SERVER_PORT",   Port); 
    MaxPlayers  = EnvInt("MAX_PLAYERS",   MaxPlayers);
    Map         = Env("SERVER_MAP",       Map);
    Gamemode    = Env("SERVER_GAMEMODE",  Gamemode);
    BackendUrl  = Env("BACKEND_URL",      BackendUrl);
    ServerToken = Env("SERVER_TOKEN",     ServerToken);
    Password    = Env("SERVER_PASSWORD",  Password);
    Description = Env("SERVER_DESCRIPTION", Description);
    
    var pubEnv = System.Environment.GetEnvironmentVariable("SERVER_PUBLIC");
    if (!string.IsNullOrEmpty(pubEnv))
        IsPublic = pubEnv.ToLower() == "true";
}

    private void LoadFromFile(string path)
    {
        var cfg = new ConfigFile();
        if (cfg.Load(path) != Error.Ok) return;

        ServerName  = (string)cfg.GetValue("server", "name",        ServerName);
        Port        = (int)   cfg.GetValue("server", "port",        Port);
        MaxPlayers  = (int)   cfg.GetValue("server", "max_players", MaxPlayers);
        Map         = (string)cfg.GetValue("server", "map",         Map);
        Gamemode    = (string)cfg.GetValue("server", "gamemode",    Gamemode);
        BackendUrl  = (string)cfg.GetValue("server", "backend_url", BackendUrl);
        ServerToken = (string)cfg.GetValue("server", "token",       ServerToken);
        Password    = (string)cfg.GetValue("server", "password",    Password);
        Description = (string)cfg.GetValue("server", "description", Description);
        IsPublic    = (bool)  cfg.GetValue("server", "public",      IsPublic);

        GD.Print("[ServerConfig] Loaded overrides from server_config.cfg");
    }

    private static string Env(string key, string fallback)
    {
        var v = System.Environment.GetEnvironmentVariable(key);
        return string.IsNullOrEmpty(v) ? fallback : v;
    }

    private static int EnvInt(string key, int fallback)
    {
        var v = System.Environment.GetEnvironmentVariable(key);
        return int.TryParse(v, out var result) ? result : fallback;
    }
}