using Godot;
using System.Collections.Generic;

public partial class NetworkManager : Node
{
    [Export] public float SyncInterval      = 0.05f;
    [Export] public float InterpolationSpeed = 15.0f;

    private sealed class PlayerState
    {
        public Vector2 Position;
        public float   Rotation;
        public int     Direction;
        public string  AnimState  = "idle";
        public bool    Peeking;
        public Vector2 MouseTarget;
    }

    private readonly Dictionary<int, PlayerState> _states   = new();
    private readonly Dictionary<int, float>        _lastSync = new();

    private DedicatedServer _dedicatedServer;

    public override void _EnterTree()
    {
        Multiplayer.PeerConnected    += OnPeerJoined;
        Multiplayer.PeerDisconnected += OnPeerLeft;
    }

    public override void _Ready()
    {
        _dedicatedServer = GetNodeOrNull<DedicatedServer>("/root/DedicatedServer");
    }

    public override void _ExitTree()
    {
        Cleanup();
    }

    public override void _Process(double delta)
    {
        if (Multiplayer.MultiplayerPeer == null) return;

        foreach (var kvp in _states)
        {
            if (kvp.Key == Multiplayer.GetUniqueId()) continue;

            var player = GetPlayer(kvp.Key);
            if (player is Node2D node)
            {
                if (ShouldSkipInterpolation(player)) continue;
                node.GlobalPosition = node.GlobalPosition.Lerp(kvp.Value.Position, InterpolationSpeed * (float)delta);
                node.Rotation       = Mathf.LerpAngle(node.Rotation, kvp.Value.Rotation, InterpolationSpeed * (float)delta);
            }
        }
    }

    private bool IsAuthorizedSender(int peerId)
    {
        if (_dedicatedServer == null) return true;
        return _dedicatedServer.IsAuthenticated(peerId);
    }

    private bool ShouldSkipInterpolation(Node player)
    {
        if (player is Mob mob)
        {
            var interaction = mob.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
            if (interaction?.GetPulledBy() != null) return true;
        }
        return false;
    }

    private void OnPeerJoined(long id)
    {
        var peerId = (int)id;
        _states.Remove(peerId);
        _lastSync.Remove(peerId);

        var discord     = GetNodeOrNull<DiscordRPC>("/root/DiscordRpc");
        var gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
        if (discord == null || gameManager == null) return;

        if (gameManager.IsHost)
            discord.SetHosting(gameManager.ServerName, gameManager.PlayerCount, gameManager.MaxPlayers);
        else
            discord.SetInGame(gameManager.ServerName, gameManager.PlayerCount, gameManager.MaxPlayers, gameManager.CurrentMap, gameManager.Gamemode);
    }

    private void OnPeerLeft(long id)
    {
        var peerId = (int)id;
        _states.Remove(peerId);
        _lastSync.Remove(peerId);
    }

    public void SyncTransform(int peerId, Vector2 position, float rotation)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;

        _lastSync[peerId] = 0.0f;
        Rpc(MethodName.OnTransformSync, peerId, position, rotation);
    }

    public void SyncDirection(int peerId, int direction)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnDirectionSync, peerId, direction);
    }

    public void SyncState(int peerId, string state)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnStateSync, peerId, state);
    }

    public void SyncPeeking(int peerId, bool peeking)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnPeekingSync, peerId, peeking);
    }

    public void SyncMouseTarget(int peerId, Vector2 target)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnMouseSync, peerId, target);
    }

    public void SyncHeadFrame(int peerId, int frame)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnHeadSync, peerId, frame);
    }

    public void SyncGrabbedPosition(int peerId, Vector2 position)
    {
        if (Multiplayer.MultiplayerPeer == null) return;
        if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId()) return;
        Rpc(MethodName.OnGrabbedPositionSync, peerId, position);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
    private void OnTransformSync(int peerId, Vector2 position, float rotation)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).Position = position;
        GetOrCreateState(peerId).Rotation = rotation;
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void OnDirectionSync(int peerId, int direction)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).Direction = direction;
        var player = GetPlayer(peerId);
        player?.GetNodeOrNull("SpriteSystem")?.Call("SetDirection", direction);
        player?.GetNodeOrNull<MovementController>("MovementController")?.SetNetworkFacing(direction);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void OnStateSync(int peerId, string state)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).AnimState = state;
        var player = GetPlayer(peerId);
        player?.GetNodeOrNull("SpriteSystem")?.Call("SetState", state);
        player?.GetNodeOrNull<MovementController>("MovementController")?.SetNetworkState(state);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void OnPeekingSync(int peerId, bool peeking)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).Peeking = peeking;
        var player = GetPlayer(peerId);
        player?.GetNodeOrNull("SpriteSystem")?.Call("SetPeeking", peeking);
        player?.GetNodeOrNull<MovementController>("MovementController")?.SetNetworkPeeking(peeking);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
    private void OnMouseSync(int peerId, Vector2 target)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).MouseTarget = target;
        GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetMouseTarget", target);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
    private void OnHeadSync(int peerId, int frame)
    {
        if (peerId == Multiplayer.GetUniqueId()) return;
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetHeadFrame", frame);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void OnGrabbedPositionSync(int peerId, Vector2 position)
    {
        if (Multiplayer.IsServer() && !IsAuthorizedSender(Multiplayer.GetRemoteSenderId())) return;

        GetOrCreateState(peerId).Position = position;
        if (GetPlayer(peerId) is Node2D node)
            node.GlobalPosition = position;
    }

    private PlayerState GetOrCreateState(int peerId)
    {
        if (!_states.ContainsKey(peerId))
        {
            _states[peerId] = new PlayerState
            {
                Position    = Vector2.Zero,
                Rotation    = 0.0f,
                Direction   = 0,
                AnimState   = "idle",
                Peeking     = false,
                MouseTarget = Vector2.Zero
            };
        }
        return _states[peerId];
    }

    public Vector2? GetLastKnownPosition(int peerId) =>
        _states.TryGetValue(peerId, out var state) ? state.Position : null;

    public void UpdatePositionCache(int peerId, Vector2 position) =>
        GetOrCreateState(peerId).Position = position;

    private Node GetPlayer(int peerId)
    {
        var world = GetTree().GetFirstNodeInGroup("World");
        return world?.GetNodeOrNull(peerId.ToString());
    }

    public void Cleanup()
    {
        _states.Clear();
        _lastSync.Clear();
    }
}
