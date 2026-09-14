using Godot;
using GodotStation.Core.Net;
using GodotStation.Core.Subsystems;
using GodotStation.Core.Testing;
using GodotStation.Core.World;
using GodotStation.Game.Mobs;
using GodotStation.Game.Objects.Items;
using GodotStation.Game.World;

namespace GodotStation.Game;

// Top-level scene script for the main scene. Owns nothing gameplay-specific
// itself - it wires NetworkManager/TickerSubsystem events to "load the map"
// and "spawn a mob for this peer," which is the whole Phase 2 connect ->
// spawn -> lobby -> round deliverable. Later phases extend the spawn/round
// flow here rather than each inventing their own bootstrap.
public partial class GameRoot : Node2D
{
    private const string PlayerScenePath = "res://Scenes/Game/Human.tscn";
    private const string TestMapScenePath = "res://Scenes/Maps/TestMap.tscn";

    // Fired on every peer once THEIR OWN mob (matching their local unique id)
    // has been spawned - the HUD (GDScript, can't reach into C# spawn flow
    // directly) binds to a specific PlayerMob instance by listening for this
    // rather than polling for one to appear.
    [Signal] public delegate void LocalPlayerSpawnedEventHandler(Node mob);

    private NetworkManager? _network;
    private TickerSubsystem? _ticker;
    private Node2D? _world;
    private Node2D? _playersContainer;
    private MapBootstrap? _activeMap;
    private TestHarnessConfig? _testConfig;

    public override void _Ready()
    {
        _network = GetNode<NetworkManager>("/root/NetworkManager");
        _ticker = GetNode<SubsystemManager>("/root/SubsystemManager").GetSubsystem<TickerSubsystem>();
        _world = GetNode<Node2D>("World");
        _playersContainer = GetNode<Node2D>("World/Players");
        _testConfig = GetNode<TestHarnessConfig>("/root/TestHarnessConfig");

        if (_ticker != null) _ticker.StateChanged += OnRoundStateChanged;
        if (_network != null) _network.PeerConnected += OnPeerConnected;
        if (_network != null) _network.ServerCreated += OnServerCreated;
    }

    // Automated test scenarios only (see Tools/multiplayer_tests/) - skips
    // waiting for the host's real "Start Round" UI click. Real play never
    // sets this flag, so this is a no-op for every normal session.
    private void OnServerCreated()
    {
        if (_testConfig != null && _testConfig.AutoStartRound)
        {
            ServerStartRound();
        }
    }

    // Called by the host's "Start Round" UI action once - not automatic on
    // Host(), so a host can wait for other players to join first.
    public void ServerStartRound()
    {
        if (_network == null || !_network.IsServer) return;
        _ticker?.StartRound();
    }

    // Debug/QA hook for exercising both movement backends (see the M2
    // roadmap's grid/pixel toggle requirement) until there's a real settings
    // UI for it. Host-only, F9, broadcast so every peer's MovementController
    // (a static/per-process field - not networked on its own) stays in sync.
    // Grid is the default and this only ever changes it at the host's request.
    public override void _UnhandledInput(InputEvent @event)
    {
        if (_network == null || !_network.IsServer) return;
        if (@event is not InputEventKey { Pressed: true, Echo: false, Keycode: Key.F9 }) return;

        var next = MovementController.GlobalMode == MovementMode.Grid ? MovementMode.Pixel : MovementMode.Grid;
        Rpc(nameof(SetMovementModeRpc), (int)next);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SetMovementModeRpc(int mode)
    {
        MovementController.GlobalMode = (MovementMode)mode;
        GD.Print($"[GameRoot] Movement mode set to {MovementController.GlobalMode}.");
    }

    private void OnRoundStateChanged(RoundState previous, RoundState next)
    {
        if (next != RoundState.Playing) return;

        // TickerSubsystem state changes only ever happen server-side, so the
        // round start must be broadcast for clients to build the map too.
        if (_network == null || !_network.IsServer) return;

        Rpc(nameof(RoundStartedRpc));

        SpawnPlayerForPeer(1); // the server's own local player
        foreach (var peerId in Multiplayer.GetPeers())
        {
            SpawnPlayerForPeer(peerId);
        }
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void RoundStartedRpc() => LoadMap();

    private void OnPeerConnected(long peerId)
    {
        // Late join mid-round - only the server decides to spawn; other
        // peers just receive the resulting SpawnPlayerRpc broadcast. The
        // round-start broadcast predates this peer, so send it directly.
        if (_network == null || !_network.IsServer) return;
        if (_ticker == null || _ticker.State != RoundState.Playing) return;

        RpcId(peerId, nameof(RoundStartedRpc));
        SpawnPlayerForPeer(peerId);

        // World-state catch-up for the joining peer only - everyone else
        // already has this state and doesn't need it replayed. Relies on
        // RoundStartedRpc (map load) having already been processed on that
        // peer by the time these arrive, which reliable-ordered delivery on
        // the same sender->receiver channel guarantees.
        var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
        foreach (var occupant in worldGrid.GetAllOccupants())
        {
            if (occupant is Item item) item.ReplayGroundStateTo(peerId);
        }
    }

    private void LoadMap()
    {
        if (_activeMap != null) return;
        if (_world == null) return;

        var scene = GD.Load<PackedScene>(TestMapScenePath);
        if (scene == null)
        {
            GD.PrintErr($"[GameRoot] Failed to load map scene at {TestMapScenePath}.");
            return;
        }

        _activeMap = scene.Instantiate<MapBootstrap>();
        _world.AddChild(_activeMap);
    }

    private void SpawnPlayerForPeer(long peerId)
    {
        // Spawn-by-job: assigns the fallback role (Rifleman) for anyone who
        // hasn't picked one - the lobby job-selection UI (P2) will populate
        // real choices before this runs. The job name rides the spawn RPC
        // so every peer labels the mob identically.
        var job = GetNode<Jobs.JobManager>("/root/JobManager").AssignFallback(peerId);
        var spawnPosition = _activeMap?.GetNextSpawnWorldPosition() ?? Vector2.Zero;
        Rpc(nameof(SpawnPlayerRpc), peerId, spawnPosition, job);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
    private void SpawnPlayerRpc(long peerId, Vector2 position, string job)
    {
        if (_playersContainer == null) return;

        var scene = GD.Load<PackedScene>(PlayerScenePath);
        if (scene == null)
        {
            GD.PrintErr($"[GameRoot] Failed to load player scene at {PlayerScenePath}.");
            return;
        }

        var mob = scene.Instantiate<PlayerMob>();
        mob.Name = $"Player_{peerId}";
        mob.OwnerPeerId = peerId;
        mob.Position = position;
        mob.AtomName = job; // examine shows the role until real character names exist (P2 preferences)
        mob.SetMultiplayerAuthority(1); // always the server, see PlayerMob's header comment

        _playersContainer.AddChild(mob);

        if (peerId == Multiplayer.GetUniqueId())
        {
            EmitSignal(SignalName.LocalPlayerSpawned, mob);
        }

        if (Multiplayer.IsServer())
        {
            var worldGrid = GetNode<WorldGrid>("/root/WorldGrid");
            var cell = new Vector2I(
                Mathf.FloorToInt(position.X / WorldGrid.DefaultCellSize),
                Mathf.FloorToInt(position.Y / WorldGrid.DefaultCellSize));
            worldGrid.PlaceOccupant(mob, cell);
        }
    }
}
