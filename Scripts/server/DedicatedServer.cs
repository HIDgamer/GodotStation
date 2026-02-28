using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;

public partial class DedicatedServer : Node
{
    [Signal] public delegate void PlayerAuthenticatedEventHandler(int peerId, int userId, string username, string assignedJob);
    [Signal] public delegate void PlayerAuthFailedEventHandler(int peerId, string reason);

    private sealed class PlayerInfo
    {
        public int UserId;
        public string Username = "";
        public string Job = "";
        public bool Authenticated;
    }

    private const int EnetChannelCount = 2;

    private ServerConfig _config;
    private ServerRegistrar _registrar;
    private JobManager _jobManager;
    private ServerPrivileges _privileges;
    private HttpClient _httpClient;

    private readonly Dictionary<int, PlayerInfo> _players = new();

    public int PlayerCount => _players.Count;
    public bool IsActiveServer { get; private set; }

    public override async void _Ready()
    {
        if (!ShouldRunDedicatedRuntime())
        {
            IsActiveServer = false;
            return;
        }

        IsActiveServer = true;

        _config = GetNode<ServerConfig>("/root/ServerConfig");
        _registrar = GetNode<ServerRegistrar>("/root/ServerRegistrar");
        _jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
        _privileges = GetNodeOrNull<ServerPrivileges>("/root/ServerPrivileges");
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };

        _config?.EnsureLoaded();

        if (string.IsNullOrEmpty(_config.ServerToken))
        {
            GD.PrintErr("[DedicatedServer] WARNING: SERVER_TOKEN is empty.");
            GD.PrintErr("[DedicatedServer] Backend registration will be rejected (401: No token provided).");
            GD.PrintErr("[DedicatedServer] Set SERVER_TOKEN (or SERVER_API_KEY) in env/.env and restart.");
            GD.PrintErr("[DedicatedServer] Server will continue running unregistered.");
        }

        // Wait so other autoloads complete _Ready first.
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        var peer = new ENetMultiplayerPeer();
        var err = peer.CreateServer(_config.Port, _config.MaxPlayers, EnetChannelCount);

        if (err != Error.Ok)
        {
            GD.PrintErr($"[DedicatedServer] ENet failed to listen on port {_config.Port}: {err}");
            GetTree().Quit(1);
            return;
        }

        Multiplayer.MultiplayerPeer = peer;
        Multiplayer.PeerConnected += OnPeerConnected;
        Multiplayer.PeerDisconnected += OnPeerDisconnected;
        EnsureLateJoinRpcBridge();

        GD.Print($"[DedicatedServer] '{_config.ServerName}' listening on :{_config.Port} (max {_config.MaxPlayers}, channels {EnetChannelCount})");
        GD.Print($"[DedicatedServer] Backend: {_config.BackendUrl}");

        var registered = await _registrar.Register();
        if (!registered)
            GD.PrintErr("[DedicatedServer] Backend registration failed. Running unregistered.");

        var gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
        if (gameManager != null)
            gameManager.StartDedicatedLobby();
        else
            GD.PrintErr("[DedicatedServer] GameManager not found; dedicated lobby did not start.");
    }

    private static bool ShouldRunDedicatedRuntime()
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

    private void EnsureLateJoinRpcBridge()
    {
        var root = GetTree().Root;
        if (root == null)
            return;

        var communications = root.GetNodeOrNull<Node>("Communications");
        if (communications == null)
        {
            communications = new Node { Name = "Communications" };
            root.AddChild(communications);
        }

        if (communications.GetNodeOrNull<Node>("LateJoinLobbyUI") != null)
            return;

        var proxy = new LateJoinLobbyServerProxy { Name = "LateJoinLobbyUI" };
        communications.AddChild(proxy);
        GD.Print("[DedicatedServer] Installed LateJoinLobby RPC bridge at /root/Communications/LateJoinLobbyUI.");
    }

    private void OnPeerConnected(long id)
    {
        var peerId = (int)id;
        if (!_players.ContainsKey(peerId))
            _players[peerId] = new PlayerInfo { Authenticated = false };
        GD.Print($"[DedicatedServer] Peer {peerId} connected; awaiting auth.");

        var timer = GetTree().CreateTimer(10.0, false);
        timer.Timeout += () =>
        {
            if (_players.TryGetValue(peerId, out var info) && !info.Authenticated)
            {
                GD.Print($"[DedicatedServer] Peer {peerId} auth timeout; kicking.");
                KickPeer(peerId);
            }
        };
    }

    private void OnPeerDisconnected(long id)
    {
        var peerId = (int)id;
        if (_players.TryGetValue(peerId, out var info))
        {
            GD.Print($"[DedicatedServer] {(string.IsNullOrEmpty(info.Username) ? $"Peer {peerId}" : info.Username)} disconnected.");
            _players.Remove(peerId);
            _jobManager?.UnassignPeer(peerId);
            _registrar.UpdatePlayerCount(_players.Count);
        }
    }

    public void BeginAuth(int peerId, string token, string preferredJob)
    {
        if (!_players.ContainsKey(peerId))
        {
            // RegisterPlayer RPC can arrive before PeerConnected handlers fire.
            // Create a placeholder player entry so auth is not dropped.
            GD.Print($"[DedicatedServer] BeginAuth arrived before PeerConnected for {peerId}; creating placeholder entry.");
            _players[peerId] = new PlayerInfo { Authenticated = false };
        }
        if (_players[peerId].Authenticated)
        {
            GD.Print($"[DedicatedServer] Peer {peerId} is already authenticated.");
            return;
        }
        RunAuthentication(peerId, token, preferredJob);
    }

    private async void RunAuthentication(int peerId, string token, string preferredJob)
    {
        if (!_players.ContainsKey(peerId))
            return;

        var (valid, userId, username) = await VerifyToken(token);

        if (!_players.ContainsKey(peerId))
            return;

        if (!valid)
        {
            GD.Print($"[DedicatedServer] Peer {peerId} auth rejected (invalid token).");
            KickPeer(peerId);
            EmitSignal(SignalName.PlayerAuthFailed, peerId, "Invalid token");
            return;
        }

        var assignedJob = AssignJob(peerId, preferredJob);

        _players[peerId] = new PlayerInfo
        {
            UserId = userId,
            Username = username,
            Job = assignedJob,
            Authenticated = true
        };

        _registrar.UpdatePlayerCount(_players.Count);
        GD.Print($"[DedicatedServer] Authenticated {username} (peer {peerId}) -> {assignedJob}");

        EmitSignal(SignalName.PlayerAuthenticated, peerId, userId, username, assignedJob);
    }

    public async Task<(bool valid, int userId, string username)> VerifyToken(string token)
    {
        try
        {
            using var req = new System.Net.Http.HttpRequestMessage(
                System.Net.Http.HttpMethod.Get, $"{_config.BackendUrl}/api/auth/me");
            req.Headers.Add("Authorization", $"Bearer {token}");

            var response = await _httpClient.SendAsync(req);
            if (!response.IsSuccessStatusCode)
                return (false, 0, "");

            var body = await response.Content.ReadAsStringAsync();
            var parser = new Json();
            if (parser.Parse(body) != Error.Ok)
                return (false, 0, "");

            var result = parser.Data.AsGodotDictionary();
            if (!result.ContainsKey("user"))
                return (false, 0, "");

            var user = result["user"].AsGodotDictionary();
            int userId = user.ContainsKey("id") ? user["id"].AsInt32() : 0;
            string uname = user.ContainsKey("username") ? user["username"].ToString() : "";
            return (true, userId, uname);
        }
        catch (Exception e)
        {
            GD.PrintErr($"[DedicatedServer] Token verify exception: {e.Message}");
            return (false, 0, "");
        }
    }

    private string AssignJob(int peerId, string preferred)
    {
        if (_jobManager == null)
            return preferred;

        if (!string.IsNullOrEmpty(preferred) && _jobManager.AssignJob(peerId, preferred))
            return preferred;

        return _jobManager.AssignJobByPriority(peerId, new Godot.Collections.Dictionary());
    }

    public string AssignJobForPeer(int peerId, string preferredJob) => AssignJob(peerId, preferredJob);

    public bool IsAuthenticated(int peerId) =>
        _players.TryGetValue(peerId, out var p) && p.Authenticated;

    public string GetPlayerUsername(int peerId) =>
        _players.TryGetValue(peerId, out var p) ? p.Username : "";

    public int GetPlayerUserId(int peerId) =>
        _players.TryGetValue(peerId, out var p) ? p.UserId : 0;

    public string GetPlayerJob(int peerId) =>
        _players.TryGetValue(peerId, out var p) ? p.Job : "";

    public IReadOnlyDictionary<int, string> GetAllUsernames()
    {
        var map = new Dictionary<int, string>();
        foreach (var kv in _players)
            map[kv.Key] = kv.Value.Username;
        return map;
    }

    public void UpdatePlayerCount(int count) => _registrar.UpdatePlayerCount(count);

    private void KickPeer(int peerId)
    {
        _players.Remove(peerId);
        if (Multiplayer.MultiplayerPeer is ENetMultiplayerPeer enet)
            enet.DisconnectPeer(peerId);
    }

    public async void Deregister()
    {
        _registrar?.Deregister();
        await Task.CompletedTask;
    }

    public override void _ExitTree()
    {
        if (IsActiveServer)
            _registrar?.Deregister();
        _httpClient?.Dispose();
    }
}
