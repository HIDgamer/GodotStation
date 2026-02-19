using Godot;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;

public partial class ServerRegistrar : Node
{
    [Signal] public delegate void RegisteredEventHandler(string serverId);
    [Signal] public delegate void RegistrationFailedEventHandler(string error);

    private HttpClient     _httpClient;
    private ServerConfig   _config;
    private Timer          _heartbeatTimer;
    private string         _serverId       = "";
    private int            _currentPlayers = 0;
    private bool           _registered     = false;

    public bool IsRegistered => _registered;

    public override void _Ready()
    {
        _config     = GetNode<ServerConfig>("/root/ServerConfig");
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };

        if (!string.IsNullOrEmpty(_config.ServerToken))
            _httpClient.DefaultRequestHeaders.Add("X-Server-Token", _config.ServerToken);

        _heartbeatTimer = new Timer
        {
            WaitTime  = 30.0f,
            Autostart = false,
            OneShot   = false
        };
        _heartbeatTimer.Timeout += OnHeartbeatTimerTick;
        AddChild(_heartbeatTimer);
    }

    public async Task<bool> Register()
    {
        try
        {
            var payload = BuildRegistrationPayload();
            var content = new StringContent(Json.Stringify(payload), Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync($"{_config.BackendUrl}/api/servers/register", content);
            var body     = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                var err = ParseError(body);
                GD.PrintErr($"[ServerRegistrar] Registration rejected ({(int)response.StatusCode}): {err}");
                EmitSignal(SignalName.RegistrationFailed, err);
                return false;
            }

            var parser = new Json();
            if (parser.Parse(body) != Error.Ok)
            {
                EmitSignal(SignalName.RegistrationFailed, "Invalid backend response");
                return false;
            }

            var result = parser.Data.AsGodotDictionary();
            _serverId   = result.ContainsKey("server_id") ? result["server_id"].ToString() : Guid.NewGuid().ToString();
            _registered = true;

            _heartbeatTimer.Start();
            GD.Print($"[ServerRegistrar] Registered. ID: {_serverId}");
            EmitSignal(SignalName.Registered, _serverId);
            return true;
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerRegistrar] Register exception: {e.Message}");
            EmitSignal(SignalName.RegistrationFailed, "Connection error");
            return false;
        }
    }

    public void UpdatePlayerCount(int count)
    {
        _currentPlayers = count;
    }

    public async void Deregister()
    {
        if (!_registered || string.IsNullOrEmpty(_serverId)) return;

        _heartbeatTimer.Stop();
        _registered = false;

        try
        {
            var payload = new Godot.Collections.Dictionary { { "server_id", _serverId } };
            var content = new StringContent(Json.Stringify(payload), Encoding.UTF8, "application/json");
            await _httpClient.PostAsync($"{_config.BackendUrl}/api/servers/deregister", content);
            GD.Print("[ServerRegistrar] Deregistered from backend.");
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerRegistrar] Deregister exception: {e.Message}");
        }
    }

    private async void OnHeartbeatTimerTick()
    {
        if (!_registered || string.IsNullOrEmpty(_serverId)) return;

        try
        {
            var payload = new Godot.Collections.Dictionary
            {
                { "server_id",       _serverId },
                { "current_players", _currentPlayers }
            };
            var content  = new StringContent(Json.Stringify(payload), Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync($"{_config.BackendUrl}/api/servers/heartbeat", content);

            if (!response.IsSuccessStatusCode)
            {
                GD.PrintErr($"[ServerRegistrar] Heartbeat rejected ({(int)response.StatusCode}). Attempting re-register.");
                _registered = false;
                await Register();
            }
        }
        catch (Exception e)
        {
            GD.PrintErr($"[ServerRegistrar] Heartbeat exception: {e.Message}");
        }
    }

    private Godot.Collections.Dictionary BuildRegistrationPayload()
    {
        return new Godot.Collections.Dictionary
        {
            { "name",             _config.ServerName },
            { "port",             _config.Port },
            { "max_players",      _config.MaxPlayers },
            { "map",              _config.Map },
            { "gamemode",         _config.Gamemode },
            { "description",      _config.Description },
            { "is_public",        _config.IsPublic },
            { "password_protected", !string.IsNullOrEmpty(_config.Password) }
        };
    }

    private static string ParseError(string body)
    {
        try
        {
            var p = new Json();
            if (p.Parse(body) == Error.Ok)
            {
                var d = p.Data.AsGodotDictionary();
                if (d.ContainsKey("error")) return d["error"].ToString();
            }
        }
        catch { }
        return "Unknown error";
    }

    public override void _ExitTree()
    {
        _httpClient?.Dispose();
    }
}
