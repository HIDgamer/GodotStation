using Godot;
using Godot.Collections;
using System.Collections.Generic;

public partial class LateJoinLobbyServerProxy : Node
{
    private readonly HashSet<int> _readyPeers = new();

    private GameManager _gameManager;
    private JobManager _jobManager;
    private DedicatedServer _dedicatedServer;

    public override void _Ready()
    {
        _gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
        _jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
        _dedicatedServer = GetNodeOrNull<DedicatedServer>("/root/DedicatedServer");

        if (_gameManager != null)
        {
            _gameManager.GameStarted += OnGameStarted;
            _gameManager.RoundEnded += OnRoundEnded;
        }
    }

    public override void _ExitTree()
    {
        if (_gameManager != null)
        {
            _gameManager.GameStarted -= OnGameStarted;
            _gameManager.RoundEnded -= OnRoundEnded;
        }
    }

    private bool IsAuthorizedSender(int claimedPeerId)
    {
        if (claimedPeerId <= 0)
            return false;

        int sender = Multiplayer.GetRemoteSenderId();
        if (sender != 0 && sender != claimedPeerId)
            return false;

        if (_dedicatedServer != null && sender != 0 && !_dedicatedServer.IsAuthenticated(claimedPeerId))
            return false;

        return true;
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ServerSetReady(int peerId, bool ready)
    {
        if (!Multiplayer.IsServer()) return;
        if (!IsAuthorizedSender(peerId)) return;

        if (ready) _readyPeers.Add(peerId);
        else _readyPeers.Remove(peerId);

        Rpc(MethodName.SyncReadyCount, _readyPeers.Count);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void SyncReadyCount(int _count)
    {
        // Dedicated server bridge only needs this RPC signature for parity with client UI.
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ClientRoundStarted()
    {
        // Dedicated server bridge only needs this RPC signature for parity with client UI.
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void RequestPriorityAssignment(int peerId)
    {
        if (!Multiplayer.IsServer()) return;
        if (!IsAuthorizedSender(peerId)) return;

        string assigned = AssignByPriority(peerId);
        if (string.IsNullOrEmpty(assigned)) assigned = "Rifleman";

        SpawnPeer(peerId, assigned);
        RpcId(peerId, MethodName.ClientNotifyAssigned, peerId, assigned);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ClientNotifyAssigned(int _peerId, string _jobName)
    {
        // Dedicated server bridge only needs this RPC signature for parity with client UI.
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void RequestSpawnAsJob(int peerId, string jobName, Dictionary charData)
    {
        if (!Multiplayer.IsServer()) return;
        if (!IsAuthorizedSender(peerId)) return;
        if (_gameManager == null) return;

        if (charData != null && charData.Count > 0)
            _gameManager.SetPeerCharacterData(peerId, charData);

        string assigned = jobName;
        if (_jobManager != null)
        {
            if (!_jobManager.AssignJob(peerId, jobName))
            {
                RpcId(peerId, MethodName.ClientJobNoLongerAvailable, jobName);
                return;
            }
        }

        if (string.IsNullOrEmpty(assigned))
            assigned = "Rifleman";

        SpawnPeer(peerId, assigned);
        RpcId(peerId, MethodName.ClientNotifyAssigned, peerId, assigned);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void ClientJobNoLongerAvailable(string _jobName)
    {
        // Dedicated server bridge only needs this RPC signature for parity with client UI.
    }

    private void OnGameStarted()
    {
        if (!Multiplayer.IsServer()) return;
        Rpc(MethodName.ClientRoundStarted);
    }

    private void OnRoundEnded()
    {
        _readyPeers.Clear();
        if (Multiplayer.IsServer())
            Rpc(MethodName.SyncReadyCount, 0);
    }

    private string AssignByPriority(int peerId)
    {
        if (_jobManager == null || _gameManager == null)
            return "";

        var charData = _gameManager.GetPeerCharacterData(peerId);
        Dictionary rolePriorities = (charData != null && charData.ContainsKey("role_priorities"))
            ? (Dictionary)charData["role_priorities"]
            : new Dictionary();

        return _jobManager.AssignJobByPriority(peerId, rolePriorities);
    }

    private void SpawnPeer(int peerId, string jobName)
    {
        if (_gameManager == null)
            return;

        _gameManager.SpawnPlayer(peerId, GetSpawnPosition(peerId), jobName);
    }

    private Vector2 GetSpawnPosition(int peerId)
    {
        var spawnPoints = GetTree().GetNodesInGroup("SpawnPoint");
        if (spawnPoints.Count == 0)
            return Vector2.Zero;

        int index = Mathf.Abs(peerId) % spawnPoints.Count;
        if (spawnPoints[index] is Node2D node2D)
            return node2D.GlobalPosition;

        return Vector2.Zero;
    }
}
