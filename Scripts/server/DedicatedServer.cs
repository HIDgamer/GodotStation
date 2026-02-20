using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;

public partial class DedicatedServer : Node
{
    private sealed class PlayerInfo
    {
        public int    UserId;
        public string Username    = "";
        public string Job         = "";
        public bool   Authenticated;
    }

    private ServerConfig    _config;
    private ServerRegistrar _registrar;
    private JobManager      _jobManager;
    private HttpClient      _httpClient;

    private readonly Dictionary<int, PlayerInfo> _players = new();

    public int PlayerCount => _players.Count;

    public override async void _Ready()
    {
        _config    = GetNode<ServerConfig>("/root/ServerConfig");
        _registrar = GetNode<ServerRegistrar>("/root/ServerRegistrar");
        _jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
        _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

        var peer = new ENetMultiplayerPeer();
        var err  = peer.CreateServer(_config.Port, _config.MaxPlayers);

        if (err != Error.Ok)
        {
            GD.PrintErr($"[DedicatedServer] ENet failed to listen on port {_config.Port}: {err}");
            GetTree().Quit(1);
            return;
        }

        Multiplayer.MultiplayerPeer    = peer;
        Multiplayer.PeerConnected      += OnPeerConnected;
        Multiplayer.PeerDisconnected   += OnPeerDisconnected;

        GD.Print($"[DedicatedServer] '{_config.ServerName}' listening on :{_config.Port} (max {_config.MaxPlayers})");

        var registered = await _registrar.Register();
        if (!registered)
            GD.PrintErr("[DedicatedServer] Backend registration failed. Running unregistered.");
    }

    private void OnPeerConnected(long id)
    {
        var peerId = (int)id;
        _players[peerId] = new PlayerInfo { Authenticated = false };
        GD.Print($"[DedicatedServer] Peer {peerId} connected — awaiting auth.");

        var timer = GetTree().CreateTimer(10.0, false);
        timer.Timeout += () =>
        {
            if (_players.TryGetValue(peerId, out var info) && !info.Authenticated)
            {
                GD.Print($"[DedicatedServer] Peer {peerId} auth timeout. Kicking.");
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

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    public void AuthenticateRpc(string token, string preferredJob)
    {
        var peerId = Multiplayer.GetRemoteSenderId();
        if (!_players.ContainsKey(peerId)) return;
        if (_players[peerId].Authenticated) return;

        CallDeferred(MethodName.RunAuthentication, peerId, token, preferredJob);
    }

    private async void RunAuthentication(int peerId, string token, string preferredJob)
    {
        if (!_players.ContainsKey(peerId)) return;

        var (valid, userId, username) = await VerifyTokenWithBackend(token);

        if (!valid)
        {
            GD.Print($"[DedicatedServer] Peer {peerId} auth rejected (invalid token).");
            RpcId(peerId, MethodName.ReceiveAuthResult, false, "");
            await Task.Delay(500);
            KickPeer(peerId);
            return;
        }

        if (!_players.ContainsKey(peerId))
            return;

        string assignedJob = AssignJob(peerId, preferredJob);

        _players[peerId] = new PlayerInfo
        {
            UserId        = userId,
            Username      = username,
            Job           = assignedJob,
            Authenticated = true
        };

        _registrar.UpdatePlayerCount(_players.Count);
        GD.Print($"[DedicatedServer] Authenticated: {username} (peer {peerId}) → job: {assignedJob}");

        RpcId(peerId, MethodName.ReceiveAuthResult, true, assignedJob);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ReceiveAuthResult(bool success, string assignedJob) { }

    private string AssignJob(int peerId, string preferred)
    {
        if (_jobManager == null) return preferred;

        if (!string.IsNullOrEmpty(preferred) && _jobManager.AssignJob(peerId, preferred))
            return preferred;

        return _jobManager.AssignJobByPriority(peerId, new Godot.Collections.Dictionary());
    }

    private async Task<(bool valid, int userId, string username)> VerifyTokenWithBackend(string token)
    {
        try
        {
            using var req = new System.Net.Http.HttpRequestMessage(
                System.Net.Http.HttpMethod.Get, $"{_config.BackendUrl}/api/auth/me");
            req.Headers.Add("Authorization", $"Bearer {token}");

            var response = await _httpClient.SendAsync(req);
            if (!response.IsSuccessStatusCode) return (false, 0, "");

            var body   = await response.Content.ReadAsStringAsync();
            var parser = new Json();
            if (parser.Parse(body) != Error.Ok) return (false, 0, "");

            var result = parser.Data.AsGodotDictionary();
            if (!result.ContainsKey("user")) return (false, 0, "");

            var user     = result["user"].AsGodotDictionary();
            int userId   = user.ContainsKey("id")       ? user["id"].AsInt32()         : 0;
            string uname = user.ContainsKey("username") ? user["username"].ToString()  : "";
            return (true, userId, uname);
        }
        catch (Exception e)
        {
            GD.PrintErr($"[DedicatedServer] Token verify exception: {e.Message}");
            return (false, 0, "");
        }
    }

    private void KickPeer(int peerId)
    {
        _players.Remove(peerId);
        if (Multiplayer.MultiplayerPeer is ENetMultiplayerPeer enet)
            enet.DisconnectPeer(peerId);
    }

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
        foreach (var kv in _players) map[kv.Key] = kv.Value.Username;
        return map;
    }

    public override void _ExitTree()
    {
        _registrar?.Deregister();
        _httpClient?.Dispose();
    }
}
