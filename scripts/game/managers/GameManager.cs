using Godot;
using Godot.Collections;
using System;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

public partial class GameManager : Node
{
	public enum GameState
	{
		Menu,
		Lobby,
		Playing,
		Hosting
	}

	[Export] public PackedScene PlayerScene;
	[Export] public int MaxPlayers = 4;
	[Export] public int DefaultPort = 7777;
	[Export] public string CurrentMap = "";
	[Export] public string Gamemode = "";
	[Export] public string CurrentVideoUid = "";
	[Export] public float LobbyTimeLeft = 300.0f;
	[Export] public bool LobbyTimerPaused = false;
	[Export] public float IngameTime = 0.0f;
	[Export] public int PlayerCount = 0;
	[Export] public bool ChatInputActive = false;
	[Export] public string ServerName = "";
	[Export] public string ServerDescription = "";
	[Export] public bool PasswordProtected = false;
	[Export] public string CurrentMusicName = "";
	[Export] public string CurrentMediaType = "";
	[Export] public string CurrentMediaPath = "";
	[Export] public int CurrentMediaLoops = 0;
	[Export] public float CurrentMediaVolume = 0.5f;

	private GameState _currentGameState = GameState.Menu;
	private ENetMultiplayerPeer _peer = new();
	private Timer _lobbyTimer;
	private Timer _lobbyUpdateTimer;
	private bool _gameStarted = false;
	private bool _roundInProgress = false;

	private System.Collections.Generic.List<int> _connectedPeers = new();
	private System.Collections.Generic.Dictionary<int, string> _playerNames = new();
	private System.Collections.Generic.Dictionary<int, Dictionary> _peerCharacters = new();
	private System.Collections.Generic.Dictionary<int, System.Collections.Generic.List<long>> _messageTimestamps = new();
	private System.Collections.Generic.HashSet<int> _lateJoiners = new();

	private System.Collections.Generic.Dictionary<int, string> _peerToDiscordTag = new();
	private System.Collections.Generic.Dictionary<string, int> _discordTagToPeer = new();

	private System.Collections.Generic.Dictionary<string, string> _sleepingMobs = new();
	private System.Collections.Generic.Dictionary<string, Dictionary> _sleepingMobData = new();
	private System.Collections.Generic.HashSet<string> _roundParticipants = new();

	private System.Collections.Generic.HashSet<int> _pendingSpawnConfirm = new();

	private DedicatedServer  _dedicatedServer;
	private ServerPrivileges _serverPrivileges;
	
		private readonly System.Collections.Generic.Dictionary<int,
			(string tag, Dictionary charData, string token, string preferredJob)> _pendingAuth = new();

	private const int MAX_MESSAGES_PER_10_SECONDS = 10;
	private const int MESSAGE_COOLDOWN_MS = 500;
	private const float CHAT_PROXIMITY_RANGE = 500.0f;
	private const int MIN_NETWORK_PORT = 1024;
	private const int MAX_NETWORK_PORT = 65535;
	private const int ENET_CHANNEL_COUNT = 2;
	private const string CommunicationsScenePath = "res://Scenes/game/ui/Communications.tscn";
	private const string MainLobbyScenePath = "res://Scenes/MainMenu.tscn";
	private const string DedicatedWorldHostPath = "/root/Communications/HSplitContainer/SubViewportContainer/SubViewport";
	private const string DefaultDedicatedMapUid = "uid://dible6m71p44g";
	private static readonly string[] DefaultScreensavers = {
		"uid://m44b5scm3sf2",
		"uid://baddbapvxhyjw",
		"uid://s331mwi01abw",
		"uid://bttyceok81cxh",
		"uid://cs4b47j652yok",
		"uid://c2kq5gljee3h0"
	};

	private static readonly System.Collections.Generic.Dictionary<string, string> DedicatedMapAliases =
		new(StringComparer.OrdinalIgnoreCase)
		{
			{ "ddome", "uid://dible6m71p44g" },
			{ "dome", "uid://dible6m71p44g" },
			{ "hadleyshope", "uid://bfswxq626edux" },
			{ "hadleyhope", "uid://bfswxq626edux" }
		};

	private static readonly System.Collections.Generic.Dictionary<string, string> MapUidFallbackPaths =
		new(StringComparer.OrdinalIgnoreCase)
		{
			{ "uid://dible6m71p44g", "res://Scenes/Maps/DDome.tscn" },
			{ "uid://bfswxq626edux", "res://Scenes/Maps/Hadley's_Hope.tscn" }
		};

	private JobManager _jobManager;
	private bool _isHosting = false;
	private bool _isConnected = false;
	private string _hubDiscordTag = "";

	[Signal] public delegate void PlayerJoinedEventHandler(int id);
	[Signal] public delegate void PlayerLeftEventHandler(int id);
	[Signal] public delegate void GameStartedEventHandler();
	[Signal] public delegate void PlayersUpdatedEventHandler();
	[Signal] public delegate void LobbyTimeoutEventHandler();
	[Signal] public delegate void ConnectionFailedEventHandler();
	[Signal] public delegate void ChatMessageReceivedEventHandler(int senderPeerId, string senderName, string message, string mode);
	[Signal] public delegate void BuildActionReceivedEventHandler(int peerId, string action, Dictionary data);
	[Signal] public delegate void MediaSyncReceivedEventHandler(string type, string path, int loops, float volume);
	[Signal] public delegate void RequestVideoSyncEventHandler(string videoUid, int requesterId);
	[Signal] public delegate void PlayerCountChangedEventHandler(int count);
	[Signal] public delegate void GameStateChangedEventHandler(int state);
	[Signal] public delegate void LobbyStateSyncedEventHandler(float timeLeft, bool paused, string videoUid);
	[Signal] public delegate void LateJoinerTransitionedEventHandler(int peerId);
	[Signal] public delegate void RoundEndedEventHandler();

	public const string CHARACTERS_DIR = "user://characters/";
	public const int SLOT_COUNT = 10;
	private string _charactersDirOverride = null;

	public bool IsHost => _isHosting;
	public bool IsDedicatedServer => _dedicatedServer != null;
	public GameState CurrentGameState => _currentGameState;
	public bool IsGameRunning() => _gameStarted;
	public bool IsRoundInProgress() => _roundInProgress;
	public int GetCurrentGameState() => (int)_currentGameState;

	public ServerPrivileges.ServerRole GetPlayerRole(string discordTag)
	{
		if (_serverPrivileges == null) return ServerPrivileges.ServerRole.None;
		return _serverPrivileges.GetRole(discordTag);
	}

	public ServerPrivileges.ServerRole GetPeerRole(int peerId)
	{
		var tag = _peerToDiscordTag.ContainsKey(peerId) ? _peerToDiscordTag[peerId] : "";
		return GetPlayerRole(tag);
	}

	public bool LocalPlayerCanStartGame()
	{
		// Guard: Multiplayer.GetUniqueId() throws a C++ error if no peer is assigned.
		if (Multiplayer.MultiplayerPeer == null) return false;

		var peerId = Multiplayer.GetUniqueId();
		if (peerId == 1) return true; // Server process itself always has authority

		// Server-side path: _serverPrivileges is loaded and _peerToDiscordTag is populated.
		var role = GetPeerRole(peerId);
		if (role >= ServerPrivileges.ServerRole.Administrator) return true;

		// Client-side path: _serverPrivileges is null on clients, but the server stamps
		// "server_role" into character data and broadcasts it via BroadcastPlayerJoinedWithData.
		// Read our own role back from that cached data.
		if (_peerCharacters.TryGetValue(peerId, out var charData) && charData.ContainsKey("server_role"))
		{
			if (System.Enum.TryParse<ServerPrivileges.ServerRole>(
					charData["server_role"].ToString(), out var stampedRole))
				return stampedRole >= ServerPrivileges.ServerRole.Administrator;
		}

		return false;
	}

	public override void _Ready()
	{
		GD.Print("[GameManager] _Ready called.");

		PlayerScene = GD.Load<PackedScene>("uid://cj25bsb3ooj62");
		if (PlayerScene == null)
			PlayerScene = GD.Load<PackedScene>("res://Scenes/Characters/Human.tscn");
		if (PlayerScene == null)
			GD.PrintErr("[GameManager] CRITICAL: PlayerScene failed to load.");

		Multiplayer.PeerConnected      += OnPeerConnected;
		Multiplayer.PeerDisconnected   += OnPeerDisconnected;
		Multiplayer.ConnectedToServer  += OnConnectedToServer;
		Multiplayer.ConnectionFailed   += OnConnectionFailed;
		Multiplayer.ServerDisconnected += OnServerDisconnected;

		var args = OS.GetCmdlineArgs();
		for (int i = 0; i < args.Length; i++)
		{
			if (args[i] == "--profile" && i + 1 < args.Length)
			{
				_charactersDirOverride = $"user://characters_{args[i + 1]}/";
				GD.Print($"[GameManager] Profile override active: {_charactersDirOverride}");
				break;
			}
		}

		EnsureCharactersDirectory();

		// Detect dedicated server mode.
		var dedicatedNode = GetNodeOrNull<DedicatedServer>("/root/DedicatedServer");
		_dedicatedServer = (dedicatedNode != null && dedicatedNode.IsActiveServer) ? dedicatedNode : null;
		_serverPrivileges = GetNodeOrNull<ServerPrivileges>("/root/ServerPrivileges");
		if (_dedicatedServer != null)
		{
			_dedicatedServer.PlayerAuthenticated += OnDedicatedPlayerAuthenticated;
			_dedicatedServer.PlayerAuthFailed    += OnDedicatedPlayerAuthFailed;
			ApplyDedicatedServerConfig();
			GD.Print("[GameManager] Dedicated server detected - auth gate active.");
		}

		InitializeLateJoinSystem();

		var discord = GetNodeOrNull<Node>("/root/DiscordRpc");
		GameStateChanged += (stateInt) =>
		{
			var state = (GameState)stateInt;
			if (discord == null) return;
			switch (state)
			{
				case GameState.Lobby:
					if (discord.HasMethod("SetInLobby")) discord.Call("SetInLobby");
					break;
				case GameState.Playing:
					if (discord.HasMethod("SetInGame")) discord.Call("SetInGame", ServerName, PlayerCount, MaxPlayers);
					break;
				case GameState.Hosting:
					if (discord.HasMethod("SetHosting")) discord.Call("SetHosting", ServerName, PlayerCount, MaxPlayers);
					break;
			}
		};

		// Parse arguments injected by the GS-Nebula launcher (--auth-token, --discord-tag, --join-server).
		// Must run AFTER multiplayer setup so JoinServerFromHub can safely call into the network layer.
		ParseHubArguments();

		GD.Print("[GameManager] _Ready complete.");
	}

	private void InitializeLateJoinSystem()
	{
		_jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
		if (_jobManager == null)
		{
			_jobManager = new JobManager();
			_jobManager.Name = "JobManager";
			GetTree().Root.CallDeferred("add_child", _jobManager);
		}
	}

	public void SetGameState(GameState newState)
	{
		if (_currentGameState != newState)
		{
			_currentGameState = newState;
			EmitSignal(SignalName.GameStateChanged, (int)newState);
		}
	}

	public void SetChatInputActive(bool active) => ChatInputActive = active;

    private void StartLocalLobby()
    {
        if (ServerName == "") ServerName = "Local Server";
        GD.Print($"[GameManager] StartLocalLobby: port={DefaultPort} name='{ServerName}'");

        var peer = new ENetMultiplayerPeer();
        var err  = peer.CreateServer(DefaultPort, MaxPlayers, ENET_CHANNEL_COUNT);
        if (err != Error.Ok)
        {
            GD.PrintErr($"[GameManager] StartLocalLobby: CreateServer failed — {err}");
            EmitSignal(SignalName.ConnectionFailed);
            return;
        }

        peer.RefuseNewConnections = false;
        Multiplayer.MultiplayerPeer = peer;
        _peer       = peer;
        _isHosting  = true;
        PlayerCount = 1;

        SetGameState(GameState.Hosting);
        SetupLobbyTimer();

        if (Godot.FileAccess.FileExists(CommunicationsScenePath))
            GetTree().ChangeSceneToFile(CommunicationsScenePath);
        else
            GD.PrintErr($"[GameManager] Communications scene not found at '{CommunicationsScenePath}'.");
    }

	public void HostGame(int port = -1)
	{
		if (port == -1) port = DefaultPort;
		GD.Print($"[GameManager] HostGame: port={port} maxPlayers={MaxPlayers} name='{ServerName}'");

		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid host port: {port}.");
			return;
		}

		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateServer(port, MaxPlayers, ENET_CHANNEL_COUNT);
		if (error != Error.Ok)
		{
			GD.PrintErr($"[GameManager] Failed to create server on port {port}: {error}");
			return;
		}

		_peer.RefuseNewConnections = false;
		Multiplayer.MultiplayerPeer = _peer;
		PlayerCount = 1;
		_connectedPeers.Add(1);
		_isHosting = true;

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var playerData = (Dictionary)prefManager.Call("get_character_data");
			var hostName = playerData.ContainsKey("name") ? (string)playerData["name"] : "Host";
			if (string.IsNullOrEmpty(hostName)) hostName = "Host";
			_playerNames[1] = hostName;
			if (!playerData.ContainsKey("peer_id")) playerData["peer_id"] = 1;
			_peerCharacters[1] = playerData;
			if (prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", 1, playerData);
		}
		else
		{
			_playerNames[1] = "Host";
			_peerCharacters[1] = new Dictionary { { "name", "Host" }, { "peer_id", 1 } };
		}

		// Use the discord tag received from the hub at launch.
		if (!string.IsNullOrEmpty(_hubDiscordTag))
		{
			_peerToDiscordTag[1] = _hubDiscordTag;
			_discordTagToPeer[_hubDiscordTag] = 1;
		}

		SetupLobbyTimer();
		// Server registration is handled by the GS-Nebula hub — no in-game lobby call needed.
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		SetGameState(GameState.Hosting);
		if (Godot.FileAccess.FileExists(CommunicationsScenePath))
			GetTree().ChangeSceneToFile(CommunicationsScenePath);
		else
			GD.PrintErr($"[GameManager] Communications scene not found at '{CommunicationsScenePath}'. Staying on current scene.");
	}

	private void SetupLobbyTimer()
	{
		_lobbyTimer = new Timer { WaitTime = LobbyTimeLeft, OneShot = true };
		_lobbyTimer.Timeout += OnLobbyTimerTimeout;
		AddChild(_lobbyTimer);
		_lobbyTimer.Start();

		_lobbyUpdateTimer = new Timer { WaitTime = 1.0f };
		_lobbyUpdateTimer.Timeout += OnLobbyUpdateTimeout;
		AddChild(_lobbyUpdateTimer);
		_lobbyUpdateTimer.Start();
	}

	private void OnLobbyTimerTimeout()
	{
		EmitSignal(SignalName.LobbyTimeout);
		StartGame();
	}

	private void OnLobbyUpdateTimeout()
	{
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped())
		{
			LobbyTimeLeft = (float)_lobbyTimer.TimeLeft;
			PlayerCount = _connectedPeers.Count;

			if (Multiplayer.IsServer() && Multiplayer.MultiplayerPeer != null)
			{
				Rpc(MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
				Rpc(MethodName.SyncStatusInfo, CurrentMap, Gamemode, PlayerCount, CurrentMusicName, LobbyTimeLeft, LobbyTimerPaused);
			}

			EmitSignal(SignalName.PlayersUpdated);
		}
	}

	public void JoinGame(string address, int port)
	{
		GD.Print($"[GameManager] JoinGame: address='{address}' port={port}");

		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid join port: {port}.");
			EmitSignal(SignalName.ConnectionFailed);
			return;
		}

		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateClient(address, port, ENET_CHANNEL_COUNT);
		if (error == Error.Ok)
		{
			Multiplayer.MultiplayerPeer = _peer;
			_isConnected = false;
			SetGameState(GameState.Lobby);
		}
		else
		{
			GD.PrintErr($"[GameManager] Failed to create ENet client for {address}:{port}: {error}");
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	public void LeaveGame()
	{
		GD.Print("[GameManager] LeaveGame called.");
		// Server deregistration is handled by the GS-Nebula hub on process exit.
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped()) _lobbyTimer.Stop();
		_peer?.Close();
		Multiplayer.MultiplayerPeer = null;

		_isHosting = false;
		_isConnected = false;
		_gameStarted = false;
		_roundInProgress = false;
		_connectedPeers.Clear();
		_playerNames.Clear();
		_peerCharacters.Clear();
		_lateJoiners.Clear();
		_roundParticipants.Clear();
		_sleepingMobs.Clear();
		_sleepingMobData.Clear();
		_peerToDiscordTag.Clear();
		_discordTagToPeer.Clear();
		_pendingSpawnConfirm.Clear();
		_pendingAuth.Clear();
		SetGameState(GameState.Menu);
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

		public void StartGame()
		{
			if (_gameStarted) return;

		_gameStarted = true;
		_roundInProgress = true;

		if (_lobbyTimer != null) { _lobbyTimer.Stop(); _lobbyTimer.QueueFree(); _lobbyTimer = null; }
		if (_lobbyUpdateTimer != null) { _lobbyUpdateTimer.Stop(); _lobbyUpdateTimer.QueueFree(); _lobbyUpdateTimer = null; }

			if (Multiplayer.IsServer())
				Rpc(MethodName.SyncRoundState, true);

			if (Multiplayer.IsServer() && _dedicatedServer != null)
				SpawnConnectedPlayersForDedicatedRound();

			SetGameState(GameState.Playing);
			EmitSignal(SignalName.GameStarted);
		}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncRoundState(bool inProgress)
	{
		var wasInProgress = _roundInProgress;
		_roundInProgress = inProgress;

		_gameStarted = inProgress;
		if (inProgress)
		{
			if (!wasInProgress)
			{
				SetGameState(GameState.Playing);
				EmitSignal(SignalName.GameStarted);
			}
			return;
		}

		SetGameState(GameState.Lobby);
		if (!inProgress)
		{
			_roundParticipants.Clear();
			_sleepingMobs.Clear();
			_sleepingMobData.Clear();
			EmitSignal(SignalName.RoundEnded);
		}
	}

	public void EndRound()
	{
		GD.Print($"[GameManager] EndRound. isServer={Multiplayer.IsServer()} roundInProgress={_roundInProgress}");
		if (!Multiplayer.IsServer() || !_roundInProgress) return;

		_roundInProgress = false;
		_gameStarted = false;
		_roundParticipants.Clear();
		_sleepingMobs.Clear();
		_sleepingMobData.Clear();
		Rpc(MethodName.SyncRoundState, false);
		SetGameState(GameState.Lobby);
	}


		private void OnPeerConnected(long id)
		{
			var peerId = (int)id;
			if (!_connectedPeers.Contains(peerId))
				_connectedPeers.Add(peerId);
			PlayerCount = _connectedPeers.Count;

		if (Multiplayer.IsServer())
		{
				RpcId(peerId, MethodName.SyncStatusInfo,
					CurrentMap, Gamemode, PlayerCount,
					CurrentMusicName, LobbyTimeLeft, LobbyTimerPaused);

				if (!string.IsNullOrEmpty(CurrentMediaPath))
					RpcId(peerId, MethodName.ReceiveMediaSync, CurrentMediaType, CurrentMediaPath, CurrentMediaLoops, CurrentMediaVolume);

			if (_roundInProgress)
				RpcId(peerId, MethodName.SyncRoundState, true);

			foreach (var kvp in _peerCharacters)
			{
				if (kvp.Key == peerId) continue;
				var cachedName = _playerNames.ContainsKey(kvp.Key) ? _playerNames[kvp.Key] : $"Player{kvp.Key}";
				RpcId(peerId, MethodName.BroadcastPlayerJoinedWithData, kvp.Key, cachedName, kvp.Value);
			}
		}

		EmitSignal(SignalName.PlayerJoined, peerId);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	private void OnPeerDisconnected(long id)
	{
		var peerId = (int)id;

		_connectedPeers.Remove(peerId);
		_lateJoiners.Remove(peerId);
		_pendingAuth.Remove(peerId);
		PlayerCount = _connectedPeers.Count;

		var discordTag = _peerToDiscordTag.ContainsKey(peerId) ? _peerToDiscordTag[peerId] : "";
		_peerToDiscordTag.Remove(peerId);
		if (!string.IsNullOrEmpty(discordTag)) _discordTagToPeer.Remove(discordTag);

		var isRoundParticipant = _roundInProgress &&
								  !string.IsNullOrEmpty(discordTag) &&
								  _roundParticipants.Contains(discordTag);

		if (isRoundParticipant)
		{
			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());

			if (playerNode == null)
			{
				GD.PrintErr($"[GameManager] WARNING: Could not find player node '{peerId}' in World.");
			}
			else
			{
				var charData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
				if (_jobManager != null)
				{
					var job = _jobManager.GetAssignedJob(peerId);
					if (!string.IsNullOrEmpty(job)) charData["job"] = job;
				}
				_sleepingMobData[discordTag] = charData;

				var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
				stateSystem?.SetState(MobState.Sleeping);
				_sleepingMobs[discordTag] = peerId.ToString();
			}
		}
		else
		{
			_jobManager?.UnassignPeer(peerId);
			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			playerNode?.QueueFree();
		}

		_peerCharacters.Remove(peerId);
		_playerNames.Remove(peerId);

		EmitSignal(SignalName.PlayerLeft, peerId);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	private void OnConnectedToServer()
	{
		_isConnected = true;
		var peerId = Multiplayer.GetUniqueId();
		GD.Print($"[GameManager] OnConnectedToServer: peer ID = {peerId}");

		_connectedPeers.Add(peerId);

		// Discord tag and auth token come from the hub via command-line args —
		// no AccountManager autoload needed.
		var discordTag = _hubDiscordTag;
		var token      = HubAuthToken;

		if (!string.IsNullOrEmpty(discordTag))
		{
			_peerToDiscordTag[peerId] = discordTag;
			_discordTagToPeer[discordTag] = peerId;
		}

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var playerData = (Dictionary)prefManager.Call("get_character_data");
			if (!playerData.ContainsKey("peer_id")) playerData["peer_id"] = peerId;

			string preferredJob = "";
			if (playerData.ContainsKey("role_priorities"))
			{
				var priorities = playerData["role_priorities"].AsGodotDictionary();
				preferredJob = DeterminePreferredJob(priorities);
			}

			RpcId(1, MethodName.RegisterPlayer, peerId, discordTag, playerData, token, preferredJob);
		}
		else
		{
			GD.PrintErr("[GameManager] PreferenceManager not found - RegisterPlayer not sent.");
		}

		RpcId(1, MethodName.RequestCurrentVideo);

		CallDeferred(MethodName.TransitionToCommunications);
	}

	private void TransitionToCommunications()
	{
		GetTree().ChangeSceneToFile(CommunicationsScenePath);
	}

	private void OnConnectionFailed()
	{
		GD.PrintErr("[GameManager] OnConnectionFailed.");
		EmitSignal(SignalName.ConnectionFailed);
		_isConnected = false;
		Multiplayer.MultiplayerPeer = null;
		// Scene was never changed in JoinGame(), so the player is still on the
		// menu/lobby screen. Just reset game state so the UI can react.
		SetGameState(GameState.Menu);
	}

	private void OnServerDisconnected()
	{
		GD.PrintErr("[GameManager] OnServerDisconnected - returning to menu.");
		_isConnected = false;
		_gameStarted = false;
		_roundInProgress = false;
		_connectedPeers.Clear();
		_playerNames.Clear();
		_peerCharacters.Clear();
		_lateJoiners.Clear();
		_roundParticipants.Clear();
		_sleepingMobs.Clear();
		_sleepingMobData.Clear();
		_peerToDiscordTag.Clear();
		_discordTagToPeer.Clear();
		_pendingSpawnConfirm.Clear();
		_pendingAuth.Clear();
		PlayerCount = 0;
		Multiplayer.MultiplayerPeer = null;
		SetGameState(GameState.Menu);
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}


	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RegisterPlayer(int peerId, string discordTag, Dictionary characterData,
								string token, string preferredJob)
	{
		if (!Multiplayer.IsServer()) return;

		// Validate the RPC sender matches the claimed peer ID.
		var actualSender = Multiplayer.GetRemoteSenderId();
		if (actualSender != peerId)
		{
			GD.PrintErr($"[GameManager] RegisterPlayer sender mismatch: claimed={peerId} actual={actualSender}. Rejecting.");
			return;
		}

		// RegisterPlayer can race ahead of PeerConnected signal callbacks.
		// Ensure server bookkeeping includes the peer immediately.
		if (!_connectedPeers.Contains(peerId))
		{
			_connectedPeers.Add(peerId);
			PlayerCount = _connectedPeers.Count;
		}

		if (_dedicatedServer != null)
		{
			// Dedicated mode: gate on auth. Store pending and kick off async verification.
			if (_dedicatedServer.IsAuthenticated(peerId))
			{
				// Already authenticated (e.g., re-registration after reconnect).
				var username = _dedicatedServer.GetPlayerUsername(peerId);
				if (!string.IsNullOrEmpty(username)) characterData["name"] = username;
				characterData["job"] = _dedicatedServer.GetPlayerJob(peerId);
			}
			else
			{
				GD.Print($"[GameManager] Peer {peerId} registering - queueing for auth verification.");
				_pendingAuth[peerId] = (discordTag, characterData, token, preferredJob);
				_dedicatedServer.BeginAuth(peerId, token, preferredJob);
				return;
			}
		}

		ProcessPlayerRegistration(peerId, discordTag, characterData);
	}


	private void OnDedicatedPlayerAuthenticated(int peerId, int userId, string username, string assignedJob)
	{
		GD.Print($"[GameManager] DedicatedServer authenticated peer {peerId}: user='{username}' job='{assignedJob}'");

		if (!_pendingAuth.TryGetValue(peerId, out var pending))
		{
			GD.PrintErr($"[GameManager] OnDedicatedPlayerAuthenticated: no pending registration for peer {peerId}.");
			return;
		}
		_pendingAuth.Remove(peerId);

		if (!IsPeerCurrentlyConnected(peerId))
		{
			GD.Print($"[GameManager] Peer {peerId} disconnected during auth. Skipping.");
			return;
		}

		var (tag, charData, _, _) = pending;
		if (string.IsNullOrWhiteSpace(tag))
			tag = username;
		// Trust backend username over what the client sent.
		charData["name"] = username;
		charData["job"]  = assignedJob;

		ProcessPlayerRegistration(peerId, tag, charData);
	}

	private bool IsPeerCurrentlyConnected(int peerId)
	{
		if (peerId <= 0)
			return false;

		if (peerId == 1 && Multiplayer.IsServer())
			return true;

		if (Multiplayer.MultiplayerPeer == null)
			return false;

		var peers = Multiplayer.GetPeers();
		for (int i = 0; i < peers.Length; i++)
		{
			if (peers[i] == peerId)
				return true;
		}

		return _connectedPeers.Contains(peerId);
	}

	private void OnDedicatedPlayerAuthFailed(int peerId, string reason)
	{
		GD.PrintErr($"[GameManager] Auth failed for peer {peerId}: {reason}");
		_pendingAuth.Remove(peerId);
		// DedicatedServer already kicks the peer, but clean up our state.
		_connectedPeers.Remove(peerId);
		_playerNames.Remove(peerId);
		_peerCharacters.Remove(peerId);
	}


	private void ProcessPlayerRegistration(int peerId, string discordTag, Dictionary characterData)
	{
		var charName = characterData.ContainsKey("name") ? (string)characterData["name"] : "(unknown)";
		GD.Print($"[GameManager] ProcessPlayerRegistration: peer={peerId} tag='{discordTag}' name='{charName}' roundInProgress={_roundInProgress}");

		if (!string.IsNullOrEmpty(discordTag))
		{
			if (_discordTagToPeer.TryGetValue(discordTag, out var stalePeer) && stalePeer != peerId)
			{
				if (!_connectedPeers.Contains(stalePeer))
					_peerToDiscordTag.Remove(stalePeer);
			}
			_peerToDiscordTag[peerId] = discordTag;
			_discordTagToPeer[discordTag] = peerId;
		}

		if (_serverPrivileges != null && !string.IsNullOrEmpty(discordTag))
		{
			var role = _serverPrivileges.GetRole(discordTag);
			characterData["server_role"] = role.ToString();
		}

		if (_roundInProgress && !string.IsNullOrEmpty(discordTag) && _sleepingMobs.ContainsKey(discordTag))
		{
			WakeUpReturningPlayer(peerId, discordTag, characterData);
			return;
		}

		var playerName = characterData.ContainsKey("name") ? (string)characterData["name"] : $"Player{peerId}";
		_playerNames[peerId] = playerName;
		if (!characterData.ContainsKey("peer_id")) characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;

		var pref = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (pref != null && pref.HasMethod("set_peer_character_data"))
			pref.Call("set_peer_character_data", peerId, characterData);

		if (_roundInProgress)
		{
			_lateJoiners.Add(peerId);
			RpcId(peerId, MethodName.NotifyLateJoiner);
			Rpc(MethodName.BroadcastPlayerJoined, peerId, playerName);
			EmitSignal(SignalName.PlayersUpdated);
			return;
		}

		RpcId(peerId, MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		Rpc(MethodName.BroadcastPlayerJoinedWithData, peerId, playerName, characterData);
		EmitSignal(SignalName.PlayersUpdated);
	}


	private static string DeterminePreferredJob(Dictionary priorities)
	{
		if (priorities == null || priorities.Count == 0) return "";
		foreach (var key in priorities.Keys)
			if (priorities[key].ToString() == "High") return key.ToString();
		foreach (var key in priorities.Keys)
			if (priorities[key].ToString() == "Medium") return key.ToString();
		foreach (var key in priorities.Keys)
			return key.ToString();
		return "";
	}


	private void WakeUpReturningPlayer(int newPeerId, string discordTag, Dictionary incomingData)
	{
		GD.Print($"[GameManager] WakeUpReturningPlayer: newPeer={newPeerId} tag='{discordTag}'");

		var sleepingNodeName = _sleepingMobs[discordTag];
		_sleepingMobs.Remove(discordTag);

		var hasSavedData = _sleepingMobData.ContainsKey(discordTag);
		var savedData    = hasSavedData ? _sleepingMobData[discordTag] : incomingData;
		_sleepingMobData.Remove(discordTag);

		savedData["peer_id"] = newPeerId;
		_peerCharacters[newPeerId] = savedData;
		if (int.TryParse(sleepingNodeName, out var oldPeerIdForAlias) && oldPeerIdForAlias != newPeerId)
			_peerCharacters[oldPeerIdForAlias] = savedData;
		if (savedData.ContainsKey("name"))
			_playerNames[newPeerId] = (string)savedData["name"];

		var pref = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (pref != null && pref.HasMethod("set_peer_character_data"))
			pref.Call("set_peer_character_data", newPeerId, savedData);

		if (int.TryParse(sleepingNodeName, out var oldPeerId) && oldPeerId != newPeerId && _jobManager != null)
		{
			var job = _jobManager.GetAssignedJob(oldPeerId);
			if (!string.IsNullOrEmpty(job))
			{
				_jobManager.UnassignPeer(oldPeerId);
				_jobManager.AssignJob(newPeerId, job);
			}
		}

		CallDeferred(MethodName.ApplyReconnectDeferred, newPeerId, sleepingNodeName, savedData);
	}

	private void ApplyReconnectDeferred(int newPeerId, string sleepingNodeName, Dictionary savedData)
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null) { FallbackToLateJoin(newPeerId); return; }

		var playerNode = world.GetNodeOrNull<Node2D>(sleepingNodeName);
		if (playerNode == null || !IsInstanceValid(playerNode)) { FallbackToLateJoin(newPeerId); return; }

		playerNode.Name = newPeerId.ToString();
		playerNode.SetMultiplayerAuthority(newPeerId);

		if (int.TryParse(sleepingNodeName, out var oldAliasId) && oldAliasId != newPeerId)
			_peerCharacters.Remove(oldAliasId);

		var reconnectedInteraction = playerNode.GetNodeOrNull<Node>("PlayerInteractionSystem");
		if (reconnectedInteraction != null && reconnectedInteraction.HasMethod("ResyncPullStateAfterRename"))
			reconnectedInteraction.Call("ResyncPullStateAfterRename", newPeerId);

		var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		stateSystem?.SetState(MobState.Standing);

		Rpc(MethodName.ClientRenamePlayerNode, sleepingNodeName, newPeerId);

		var broadcastName = _playerNames.ContainsKey(newPeerId) ? _playerNames[newPeerId] : $"Player{newPeerId}";
		Rpc(MethodName.BroadcastPlayerJoinedWithData, newPeerId, broadcastName, savedData);
		EmitSignal(SignalName.PlayersUpdated);

		var spawnPosition = playerNode.GlobalPosition;
		var confirmTimer  = GetTree().CreateTimer(0.35);
		confirmTimer.Timeout += () =>
		{
			if (IsInstanceValid(playerNode))
				RpcId(newPeerId, MethodName.ClientReconnectConfirmed, newPeerId, spawnPosition, savedData);
		};
	}

	private void FallbackToLateJoin(int peerId)
	{
		_lateJoiners.Add(peerId);
		RpcId(peerId, MethodName.NotifyLateJoiner);
		var name = _playerNames.ContainsKey(peerId) ? _playerNames[peerId] : $"Player{peerId}";
		Rpc(MethodName.BroadcastPlayerJoined, peerId, name);
		EmitSignal(SignalName.PlayersUpdated);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientRenamePlayerNode(string oldName, int newPeerId)
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		var playerNode = world?.GetNodeOrNull<Node2D>(oldName);
		if (playerNode != null && IsInstanceValid(playerNode))
		{
			playerNode.Name = newPeerId.ToString();
			playerNode.SetMultiplayerAuthority(newPeerId);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientReconnectConfirmed(int peerId, Vector2 position, Dictionary charData)
	{
		if (peerId != Multiplayer.GetUniqueId()) return;

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
			prefManager.Call("set_peer_character_data", peerId, charData);

		var world      = GetTree().GetFirstNodeInGroup("World");
		var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());

		if (playerNode != null)
		{
			playerNode.GlobalPosition = position;
			if (playerNode.HasMethod("ApplyCharacterData"))
				playerNode.Call("ApplyCharacterData", charData);
			else if (playerNode.HasMethod("RefreshAuthority"))
				playerNode.Call("RefreshAuthority");

			playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem")?.SetState(MobState.Standing);
		}

		EmitSignal(SignalName.LateJoinerTransitioned, peerId);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void NotifyLateJoiner()
	{
		ShowLateJoinUI();
	}

	private void ShowLateJoinUI()
	{
		var communications = GetTree().GetFirstNodeInGroup("Communications")
			?? GetNodeOrNull<Node>("/root/Communications");
		if (communications != null && communications.HasMethod("show_late_join_ui"))
			communications.Call("show_late_join_ui");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastPlayerJoined(int peerId, string playerName)
	{
		_playerNames[peerId] = playerName;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastPlayerJoinedWithData(int peerId, string playerName, Dictionary charData)
	{
		_playerNames[peerId] = playerName;
		if (charData != null && charData.Count > 0)
		{
			if (!charData.ContainsKey("peer_id")) charData["peer_id"] = peerId;
			_peerCharacters[peerId] = charData;
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", peerId, charData);
		}
	}


	public void SendChatMessage(string message, string mode = "IC")
	{
		var peerId = Multiplayer.GetUniqueId();
		if (!ValidateMessageRateLimit(peerId)) return;
		var senderName = _playerNames.ContainsKey(peerId) ? _playerNames[peerId] : $"Player{peerId}";
		if (Multiplayer.IsServer())
		{
			BroadcastChatMessage(peerId, senderName, message, mode);
			Rpc(MethodName.BroadcastChatMessage, peerId, senderName, message, mode);
		}
		else
		{
			RpcId(1, MethodName.SendChatMessageRpc, peerId, message, mode);
		}
	}

	public void SendChatFromPlayer(int peerId, string message, string mode = "IC")
	{
		if (!ValidateMessageRateLimit(peerId)) return;
		var senderName = _playerNames.ContainsKey(peerId) ? _playerNames[peerId] : $"Player{peerId}";
		if (Multiplayer.IsServer())
		{
			BroadcastChatMessage(peerId, senderName, message, mode);
			Rpc(MethodName.BroadcastChatMessage, peerId, senderName, message, mode);
		}
		else
		{
			RpcId(1, MethodName.SendChatMessageRpc, peerId, message, mode);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendChatMessageRpc(int senderPeerId, string message, string mode)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(senderPeerId)) return;
		if (!ValidateMessageRateLimit(senderPeerId)) return;
		var senderName = _playerNames.ContainsKey(senderPeerId) ? _playerNames[senderPeerId] : $"Player{senderPeerId}";
		BroadcastChatMessage(senderPeerId, senderName, message, mode);
		Rpc(MethodName.BroadcastChatMessage, senderPeerId, senderName, message, mode);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastChatMessage(int senderPeerId, string senderName, string message, string mode)
	{
		EmitSignal(SignalName.ChatMessageReceived, senderPeerId, senderName, message, mode);
	}


	public void SendBuildAction(int senderPeerId, string action, Dictionary data)
	{
		if (Multiplayer.IsServer())
		{
			BroadcastBuildAction(senderPeerId, action, data);
			Rpc(MethodName.BroadcastBuildAction, senderPeerId, action, data);
		}
		else
		{
			RpcId(1, MethodName.SendBuildActionRpc, senderPeerId, action, data);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendBuildActionRpc(int senderPeerId, string action, Dictionary data)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(senderPeerId)) return;
		BroadcastBuildAction(senderPeerId, action, data);
		Rpc(MethodName.BroadcastBuildAction, senderPeerId, action, data);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastBuildAction(int peerId, string action, Dictionary data)
	{
		EmitSignal(SignalName.BuildActionReceived, peerId, action, data);
	}


		public void SyncMedia(string type, string path, int loops = 1, float volume = 0.5f)
		{
			if (!Multiplayer.IsServer()) return;
			CurrentMediaType   = type;
			CurrentMediaPath   = path;
			CurrentMediaLoops  = loops;
			CurrentMediaVolume = volume;
			if (string.Equals(type, "video", StringComparison.OrdinalIgnoreCase))
				CurrentVideoUid = path;
			if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
				CurrentMusicName = System.IO.Path.GetFileName(path);
			Rpc(MethodName.ReceiveMediaSync, type, path, loops, volume);
		}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
		private void ReceiveMediaSync(string type, string path, int loops, float volume)
		{
			CurrentMediaType   = type;
			CurrentMediaPath   = path;
			CurrentMediaLoops  = loops;
			CurrentMediaVolume = volume;
			if (string.Equals(type, "video", StringComparison.OrdinalIgnoreCase))
				CurrentVideoUid = path;
			if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
				CurrentMusicName = System.IO.Path.GetFileName(path);
			EmitSignal(SignalName.MediaSyncReceived, type, path, loops, volume);
		}

	public void RequestMediaSyncFromClient(string type, string path, int loops, float volume)
	{
		if (Multiplayer.IsServer())
		{
			SyncMedia(type, path, loops, volume);
			return;
		}

		var peer = Multiplayer.MultiplayerPeer;
		if (peer == null || peer.GetConnectionStatus() != MultiplayerPeer.ConnectionStatus.Connected)
			return;

		RpcId(1, MethodName.RequestMediaSyncRpc, Multiplayer.GetUniqueId(), type, path, loops, volume);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestMediaSyncRpc(int requesterId, string type, string path, int loops, float volume)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(requesterId)) return;

		var tag = _peerToDiscordTag.ContainsKey(requesterId) ? _peerToDiscordTag[requesterId] : "";
		if (_serverPrivileges != null && !_serverPrivileges.CanStartGame(tag))
		{
			GD.Print($"[GameManager] RequestMediaSync denied: peer {requesterId} ('{tag}') lacks permission.");
			return;
		}

		SyncMedia(type, path, Mathf.Clamp(loops, 0, 99), Mathf.Clamp(volume, 0.0f, 1.0f));
	}

		private void SpawnConnectedPlayersForDedicatedRound()
		{
			if (_jobManager == null)
				_jobManager = GetNodeOrNull<JobManager>("/root/JobManager");

			foreach (var peerId in _connectedPeers.ToArray())
			{
				if (peerId <= 1) continue;
				if (_pendingAuth.ContainsKey(peerId)) continue;

				var charData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
				var assignedJob = ResolveDedicatedJobForPeer(peerId, charData);
				var spawnPosition = GetSpawnPositionForPeer(peerId);

				SpawnPlayer(peerId, spawnPosition, assignedJob);
			}
		}

		private string ResolveDedicatedJobForPeer(int peerId, Dictionary charData)
		{
			string assignedJob = _jobManager?.GetAssignedJob(peerId) ?? "";
			if (!string.IsNullOrWhiteSpace(assignedJob))
				return assignedJob;

			string requestedJob = "";
			if (charData != null && charData.ContainsKey("job"))
				requestedJob = charData["job"].ToString();

			Dictionary priorities = new();
			if (charData != null && charData.ContainsKey("role_priorities"))
				priorities = charData["role_priorities"].AsGodotDictionary();

			if (_jobManager != null)
			{
				if (!string.IsNullOrWhiteSpace(requestedJob) && _jobManager.AssignJob(peerId, requestedJob))
					assignedJob = requestedJob;
				else
					assignedJob = _jobManager.AssignJobByPriority(peerId, priorities);
			}
			else
			{
				assignedJob = requestedJob;
			}

			if (string.IsNullOrWhiteSpace(assignedJob))
				assignedJob = "Rifleman";

			if (charData != null)
				charData["job"] = assignedJob;

			return assignedJob;
		}

		private Vector2 GetSpawnPositionForPeer(int peerId)
		{
			var spawnPoints = GetTree().GetNodesInGroup("SpawnPoint");
			if (spawnPoints.Count == 0)
				return Vector2.Zero;

			var index = Mathf.Abs(peerId) % spawnPoints.Count;
			if (spawnPoints[index] is Node2D spawnNode)
				return spawnNode.GlobalPosition;

			return Vector2.Zero;
		}



	public void StartDedicatedLobby()
	{
		if (_dedicatedServer == null)
		{
			GD.PrintErr("[GameManager] StartDedicatedLobby called but not in dedicated mode.");
			return;
		}

		ApplyDedicatedServerConfig();
		if (!EnsureDedicatedWorldLoaded())
			GD.PrintErr("[GameManager] Dedicated world failed to load; spawn requests will fail.");

		if (string.IsNullOrEmpty(CurrentVideoUid))
		{
			var rng = new Random();
			CurrentVideoUid = DefaultScreensavers[rng.Next(DefaultScreensavers.Length)];
			GD.Print($"[GameManager] Dedicated lobby screensaver: {CurrentVideoUid}");
		}

		GD.Print("[GameManager] Starting dedicated server lobby countdown.");
		_isHosting = true;
		if (_lobbyTimer == null)
			SetupLobbyTimer();
		SetGameState(GameState.Lobby);
	}

	private void ApplyDedicatedServerConfig()
	{
		var config = GetNodeOrNull<ServerConfig>("/root/ServerConfig");
		if (config == null)
		{
			GD.PrintErr("[GameManager] Dedicated mode: ServerConfig not found.");
			return;
		}

		config.EnsureLoaded();

		ServerName = string.IsNullOrWhiteSpace(config.ServerName) ? "USCMGS" : config.ServerName;
		ServerDescription = config.Description ?? "";
		PasswordProtected = !string.IsNullOrEmpty(config.Password);
		MaxPlayers = Mathf.Max(1, config.MaxPlayers);
		DefaultPort = config.Port;
		Gamemode = string.IsNullOrWhiteSpace(config.Gamemode) ? "PVE" : config.Gamemode;
		CurrentMap = NormalizeMapReference(config.Map);
	}

	private string NormalizeMapReference(string rawMap)
	{
		if (string.IsNullOrWhiteSpace(rawMap))
			return DefaultDedicatedMapUid;

		var trimmed = rawMap.Trim();
		if (trimmed.StartsWith("uid://", StringComparison.OrdinalIgnoreCase) ||
			trimmed.StartsWith("res://", StringComparison.OrdinalIgnoreCase))
		{
			return trimmed;
		}

		var aliasKey = new string(trimmed.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
		return DedicatedMapAliases.TryGetValue(aliasKey, out var normalized) ? normalized : trimmed;
	}

	private bool EnsureDedicatedWorldLoaded()
	{
		var existingWorld = GetTree().GetFirstNodeInGroup("World");
		if (existingWorld != null)
		{
			var host = EnsureDedicatedWorldHostNode();
			if (host != null && existingWorld.GetParent() != host)
				existingWorld.Reparent(host);
			return true;
		}

		var mapReference = string.IsNullOrWhiteSpace(CurrentMap) ? DefaultDedicatedMapUid : CurrentMap;
		PackedScene mapScene = GD.Load<PackedScene>(mapReference);

		if (mapScene == null && MapUidFallbackPaths.TryGetValue(mapReference, out var fallbackPath))
			mapScene = GD.Load<PackedScene>(fallbackPath);

		if (mapScene == null)
		{
			GD.PrintErr($"[GameManager] Dedicated map failed to load: '{mapReference}'.");
			return false;
		}

		var world = mapScene.Instantiate<Node>();
		if (world == null)
		{
			GD.PrintErr($"[GameManager] Failed to instantiate map '{mapReference}'.");
			return false;
		}

		if (!world.IsInGroup("World"))
			world.AddToGroup("World");

		var worldHost = EnsureDedicatedWorldHostNode();
		if (worldHost == null)
		{
			GD.PrintErr("[GameManager] Dedicated world host node could not be created.");
			return false;
		}

		worldHost.AddChild(world);
		GD.Print($"[GameManager] Dedicated world loaded: '{world.GetPath()}' from '{mapReference}'.");
		return true;
	}

	private Node EnsureDedicatedWorldHostNode()
	{
		var existing = GetNodeOrNull<Node>(DedicatedWorldHostPath);
		if (existing != null) return existing;

		var root = GetTree().Root;
		if (root == null) return null;

		var communications = EnsureNamedChild(root, "Communications");
		var split = EnsureNamedChild(communications, "HSplitContainer");
		var subViewportContainer = EnsureNamedChild(split, "SubViewportContainer");
		return EnsureNamedChild(subViewportContainer, "SubViewport");
	}

	private static Node EnsureNamedChild(Node parent, string childName)
	{
		var child = parent.GetNodeOrNull<Node>(childName);
		if (child != null) return child;

		child = new Node { Name = childName };
		parent.AddChild(child);
		return child;
	}


	public void ToggleLobbyPause()
	{
		if (_lobbyTimer == null) return;

		if (Multiplayer.IsServer())
		{
			// (only the server process calls this directly via admin commands).
			LobbyTimerPaused   = !LobbyTimerPaused;
			_lobbyTimer.Paused = LobbyTimerPaused;
			Rpc(MethodName.SyncLobbyState, (float)_lobbyTimer.TimeLeft, LobbyTimerPaused, CurrentVideoUid);
		}
		else
		{
			RpcId(1, MethodName.RequestToggleLobbyPause, Multiplayer.GetUniqueId());
		}
	}

	public void ForceStartFromLobby()
	{
		if (_gameStarted) return;

		if (Multiplayer.IsServer())
		{
			StartGame();
		}
		else
		{
			RpcId(1, MethodName.RequestStartGame, Multiplayer.GetUniqueId());
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestStartGame(int requesterId)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(requesterId)) return;

		var tag = _peerToDiscordTag.ContainsKey(requesterId) ? _peerToDiscordTag[requesterId] : "";

		if (_serverPrivileges != null && !_serverPrivileges.CanStartGame(tag))
		{
			GD.Print($"[GameManager] RequestStartGame denied: peer {requesterId} ('{tag}') lacks permission.");
			return;
		}

		if (_gameStarted) return;
		GD.Print($"[GameManager] RequestStartGame approved for peer {requesterId} ('{tag}').");
		StartGame();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestToggleLobbyPause(int requesterId)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(requesterId)) return;
		if (_lobbyTimer == null) return;

		var tag = _peerToDiscordTag.ContainsKey(requesterId) ? _peerToDiscordTag[requesterId] : "";

		if (_serverPrivileges != null && !_serverPrivileges.CanDelayGame(tag))
		{
			GD.Print($"[GameManager] RequestToggleLobbyPause denied: peer {requesterId} ('{tag}') lacks permission.");
			return;
		}

		LobbyTimerPaused   = !LobbyTimerPaused;
		_lobbyTimer.Paused = LobbyTimerPaused;
		GD.Print($"[GameManager] Lobby timer {(LobbyTimerPaused ? "paused" : "resumed")} by peer {requesterId} ('{tag}').");
		Rpc(MethodName.SyncLobbyState, (float)_lobbyTimer.TimeLeft, LobbyTimerPaused, CurrentVideoUid);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestCurrentVideo()
	{
		if (!Multiplayer.IsServer()) return;
		var requesterId = Multiplayer.GetRemoteSenderId();
		if (requesterId > 0 && !string.IsNullOrEmpty(CurrentVideoUid))
			RpcId(requesterId, MethodName.ReceiveVideoSync, CurrentVideoUid, 0.0f);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveVideoSync(string videoUid, float positionSeconds)
	{
		CurrentVideoUid = videoUid;
		if (!string.IsNullOrEmpty(videoUid))
			EmitSignal(SignalName.MediaSyncReceived, "video", videoUid, 0, 0.5f);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStatusInfo(string mapName, string gamemode, int currentPlayers,
								string musicName, float timeLeft, bool paused)
	{
		if (!string.IsNullOrEmpty(mapName))    CurrentMap   = mapName;
		if (!string.IsNullOrEmpty(gamemode))   Gamemode     = gamemode;
		PlayerCount = currentPlayers;
		if (!string.IsNullOrEmpty(musicName))  CurrentMusicName = musicName;
		if (timeLeft >= 0.0f) LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLobbyState(float timeLeft, bool paused, string videoUid)
	{
		LobbyTimeLeft    = timeLeft;
		LobbyTimerPaused = paused;
		CurrentVideoUid  = videoUid;
		EmitSignal(SignalName.LobbyStateSynced, timeLeft, paused, videoUid);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIngameTime(float time) => IngameTime = time;

	// Item spawn compatibility endpoint used by AdminSpawnPopup.gd.
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	public void RequestSpawnItem(string scenePath, Vector2 position, int amount)
	{
		if (Multiplayer.IsServer())
		{
			var senderId = Multiplayer.GetRemoteSenderId();
			if (senderId > 0)
			{
				if (_serverPrivileges == null)
				{
					// Player-hosted mode: only host is allowed to spawn via RPC.
					if (senderId != 1)
					{
						GD.Print($"[GameManager] RequestSpawnItem denied: peer {senderId} is not host.");
						return;
					}
				}
				else
				{
					var tag = _peerToDiscordTag.ContainsKey(senderId) ? _peerToDiscordTag[senderId] : "";
					if (!_serverPrivileges.CanStartGame(tag))
					{
						GD.Print($"[GameManager] RequestSpawnItem denied: peer {senderId} ('{tag}') lacks permission.");
						return;
					}
				}
			}

			SpawnItemInternal(scenePath, position, amount);
			return;
		}

		var peer = Multiplayer.MultiplayerPeer;
		if (peer == null || peer.GetConnectionStatus() != MultiplayerPeer.ConnectionStatus.Connected)
		{
			GD.PrintErr("[GameManager] RequestSpawnItem ignored: not connected.");
			return;
		}

		RpcId(1, MethodName.RequestSpawnItem, scenePath, position, amount);
	}

	private void SpawnItemInternal(string scenePath, Vector2 position, int amount)
	{
		if (!Multiplayer.IsServer()) return;
		if (string.IsNullOrWhiteSpace(scenePath)) return;

		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null && _dedicatedServer != null)
		{
			EnsureDedicatedWorldLoaded();
			world = GetTree().GetFirstNodeInGroup("World");
		}
		if (world == null)
		{
			GD.PrintErr("[GameManager] SpawnItemInternal: World not found.");
			return;
		}

		var scene = GD.Load<PackedScene>(scenePath);
		if (scene == null)
		{
			GD.PrintErr($"[GameManager] SpawnItemInternal: Failed to load '{scenePath}'.");
			return;
		}

		int clampedAmount = Mathf.Clamp(amount, 1, 20);
		for (int i = 0; i < clampedAmount; i++)
		{
			var instance = scene.Instantiate<Node>();
			var spawnPos = position + new Vector2((i % 4) * 8, (i / 4) * 8);

			if (instance is Node2D node2D)
				node2D.GlobalPosition = spawnPos;

			if (instance.HasMethod("PrepareSpawn"))
				instance.Call("PrepareSpawn", spawnPos);

			world.CallDeferred("add_child", instance, true);

			if (instance.HasMethod("InitAtPosition"))
				instance.CallDeferred("InitAtPosition", spawnPos);
		}
	}


	public void SpawnPlayer(int peerId, Vector2 position, string jobName)
	{
		if (!Multiplayer.IsServer())
		{
			GD.PrintErr("[GameManager] SpawnPlayer called on non-server. Aborting.");
			return;
		}

		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null && _dedicatedServer != null)
		{
			EnsureDedicatedWorldLoaded();
			world = GetTree().GetFirstNodeInGroup("World");
		}
		if (world == null) { GD.PrintErr("[GameManager] SpawnPlayer: World not found."); return; }

		if (PlayerScene == null)
		{
			PlayerScene = GD.Load<PackedScene>("uid://cj25bsb3ooj62") ??
						  GD.Load<PackedScene>("res://Scenes/Characters/Human.tscn");
		}
		if (PlayerScene == null)
		{
			GD.PrintErr("[GameManager] SpawnPlayer: PlayerScene is null.");
			return;
		}

		var existing = world.GetNodeOrNull<Node2D>(peerId.ToString());
		if (existing != null)
		{
			if (_pendingSpawnConfirm.Remove(peerId))
				GD.Print($"[GameManager] Cancelled stale deferred spawn confirmation for peer {peerId}.");
			existing.SetMultiplayerAuthority(peerId);
			existing.ProcessMode = ProcessModeEnum.Inherit;
			existing.GetNodeOrNull<MobStateSystem>("MobStateSystem")?.SetState(MobState.Standing);

			var charData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
			charData["job"] = jobName;
			_peerCharacters[peerId] = charData;
			if (existing.HasMethod("ApplyCharacterData"))
				existing.Call("ApplyCharacterData", charData);

			if (peerId == Multiplayer.GetUniqueId())
				CallDeferred(MethodName.ClientSpawnConfirmed, peerId, existing.GlobalPosition, jobName, charData);
			else
				RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, existing.GlobalPosition, jobName, charData);
			return;
		}

		var playerInstance = PlayerScene.Instantiate<Node2D>();
		playerInstance.Name = peerId.ToString();

		var characterData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
		characterData["job"] = jobName;
		if (!characterData.ContainsKey("peer_id")) characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;

		playerInstance.Position = position;
		playerInstance.SetMultiplayerAuthority(peerId);
		world.CallDeferred("add_child", playerInstance);
		Rpc(MethodName.SpawnPlayerOnClients, peerId, position, characterData);
		CallDeferred(nameof(ApplyCharacterDataDeferred), playerInstance, characterData);

		var discordTag = _peerToDiscordTag.ContainsKey(peerId) ? _peerToDiscordTag[peerId] : "";
		if (!string.IsNullOrEmpty(discordTag))
			_roundParticipants.Add(discordTag);

		if (peerId == Multiplayer.GetUniqueId())
		{
			CallDeferred(MethodName.ClientSpawnConfirmed, peerId, position, jobName, characterData);
		}
		else
		{
			_pendingSpawnConfirm.Add(peerId);
			var capturedPosition  = position;
			var capturedJob       = jobName;
			var capturedData      = characterData;
			var spawnTimer        = GetTree().CreateTimer(0.05);
			spawnTimer.Timeout += () =>
			{
				if (IsInstanceValid(this) && _pendingSpawnConfirm.Remove(peerId))
					RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, capturedPosition, capturedJob, capturedData);
			};
		}

		_lateJoiners.Remove(peerId);
	}

	private void ApplyCharacterDataDeferred(Node2D playerInstance, Dictionary characterData)
	{
		if (playerInstance == null || !IsInstanceValid(playerInstance))
			return;

		if (!playerInstance.IsInsideTree())
		{
			CallDeferred(nameof(ApplyCharacterDataDeferred), playerInstance, characterData);
			return;
		}

		if (playerInstance.HasMethod("ApplyCharacterData"))
			playerInstance.Call("ApplyCharacterData", characterData);
		else if (playerInstance.Get("character_data").VariantType != Variant.Type.Nil)
			playerInstance.Set("character_data", characterData);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SpawnPlayerOnClients(int peerId, Vector2 position, Dictionary charData)
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null) { GD.PrintErr("[GameManager] SpawnPlayerOnClients: World not found."); return; }

		// Avoid duplicate spawns
		if (world.GetNodeOrNull<Node2D>(peerId.ToString()) != null) return;

		if (PlayerScene == null)
			PlayerScene = GD.Load<PackedScene>("uid://cj25bsb3ooj62") ??
						GD.Load<PackedScene>("res://Scenes/Characters/Human.tscn");
		if (PlayerScene == null) { GD.PrintErr("[GameManager] SpawnPlayerOnClients: PlayerScene null."); return; }

		var player = PlayerScene.Instantiate<Node2D>();
		player.Name = peerId.ToString();
		player.Position = position;
		player.SetMultiplayerAuthority(peerId);
		world.AddChild(player);

		if (player.HasMethod("ApplyCharacterData"))
			player.Call("ApplyCharacterData", charData);

		GD.Print($"[GameManager] SpawnPlayerOnClients: spawned peer {peerId} at {position}");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientSpawnConfirmed(int peerId, Vector2 position, string jobName, Dictionary charData)
	{
		if (charData != null && charData.Count > 0 && peerId == Multiplayer.GetUniqueId())
		{
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", peerId, charData);

			var world      = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			if (playerNode != null && playerNode.HasMethod("ApplyCharacterData"))
				playerNode.Call("ApplyCharacterData", charData);
		}
		EmitSignal(SignalName.LateJoinerTransitioned, peerId);
	}

	public void BecomeObserver(int peerId)
	{
		if (!Multiplayer.IsServer()) return;
		var observer = new Node2D { Name = $"Observer_{peerId}" };
		GetTree().GetFirstNodeInGroup("World")?.CallDeferred("add_child", observer);
		RpcId(peerId, MethodName.ClientBecomeObserver);
		_lateJoiners.Remove(peerId);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientBecomeObserver() { }

	// Communications.gd calls rpc_id(1, "SyncPlayerTransform") from clients and.
	// rpc("SyncPlayerTransform") from the server. Both paths are handled here.
	// NetworkManager's server-relay pattern is preferred for frequent per-frame syncs.

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	public void SyncPlayerTransform(int playerId, Vector2 position, float rotation)
	{
		if (!Multiplayer.IsServer()) return;

		// Remote call: validate the sender is who they claim to be and is authenticated.
		var sender = Multiplayer.GetRemoteSenderId();
		if (sender != 0 && sender != playerId) return;
		if (sender != 0 && _dedicatedServer != null && !_dedicatedServer.IsAuthenticated(sender)) return;

		Rpc(MethodName.ReceivePlayerTransform, playerId, position, rotation);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void ReceivePlayerTransform(int playerId, Vector2 position, float rotation)
	{
		var world  = GetTree().GetFirstNodeInGroup("World");
		var player = world?.GetNodeOrNull<Node2D>(playerId.ToString());
		if (player != null)
		{
			player.GlobalPosition = position;
			player.Rotation       = rotation;
		}
	}


	private bool ValidateRpcSender(int claimedSenderId)
	{
		var actualSenderId = Multiplayer.GetRemoteSenderId();
		if (actualSenderId != claimedSenderId)
		{
			GD.PrintErr($"[GameManager] RPC sender mismatch: claimed={claimedSenderId} actual={actualSenderId}. Rejecting.");
			return false;
		}
		return true;
	}

	private bool ValidateMessageRateLimit(int peerId)
	{
		if (!_messageTimestamps.ContainsKey(peerId))
			_messageTimestamps[peerId] = new System.Collections.Generic.List<long>();

		var currentTime = (long)Time.GetTicksMsec();
		var timestamps  = _messageTimestamps[peerId];
		timestamps.RemoveAll(t => currentTime - t > 10000L);

		if (timestamps.Count >= MAX_MESSAGES_PER_10_SECONDS) return false;
		if (timestamps.Count > 0 && currentTime - timestamps[^1] < MESSAGE_COOLDOWN_MS) return false;

		timestamps.Add(currentTime);
		return true;
	}


	public Dictionary GetPeerCharacterDataWithJob(int peerId)
	{
		if (_peerCharacters.ContainsKey(peerId))
		{
			var data = _peerCharacters[peerId].Duplicate();
			if (_jobManager != null)
			{
				var job = _jobManager.GetAssignedJob(peerId);
				if (!string.IsNullOrEmpty(job)) data["job"] = job;
			}
			return data;
		}
		return new Dictionary();
	}

	public Dictionary GetPeerCharacterData(int peerId) =>
		_peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId].Duplicate() : new Dictionary();

	public void SetPeerCharacterData(int peerId, Dictionary characterData)
	{
		if (!characterData.ContainsKey("peer_id")) characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;
		if (characterData.ContainsKey("name"))
		{
			var name = characterData["name"].ToString();
			if (!string.IsNullOrEmpty(name)) _playerNames[peerId] = name;
		}
	}

	public Dictionary get_peer_character_data(int peerId) => GetPeerCharacterData(peerId);
	public void set_peer_character_data(int peerId, Dictionary characterData) => SetPeerCharacterData(peerId, characterData);

	public string GetDiscordTagForPeer(int peerId) =>
		_peerToDiscordTag.TryGetValue(peerId, out var tag) ? tag : "";

	public int GetPeerForDiscordTag(string discordTag) =>
		_discordTagToPeer.TryGetValue(discordTag, out var peer) ? peer : 0;

	public bool IsLateJoiner(int peerId) => _lateJoiners.Contains(peerId);
	public void BackToLobby() => LeaveGame();


	private void EnsureCharactersDirectory()
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		if (!DirAccess.DirExistsAbsolute(dir))
			DirAccess.MakeDirRecursiveAbsolute(dir);
	}

	public Dictionary LoadSlot(int slot)
	{
		var dir     = _charactersDirOverride ?? CHARACTERS_DIR;
		var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

		foreach (char letter in letters)
		{
			var folderPath = $"{dir}{letter}/";
			if (!DirAccess.DirExistsAbsolute(folderPath)) continue;
			var dirAccess = DirAccess.Open(folderPath);
			if (dirAccess == null) continue;
			dirAccess.ListDirBegin();
			string fileName = dirAccess.GetNext();
			while (fileName != "")
			{
				if (fileName.EndsWith($"_slot{slot}.json"))
				{
					var filePath = folderPath + fileName;
					if (FileAccess.FileExists(filePath))
					{
						using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
						if (file != null)
						{
							var json = new Json();
							if (json.Parse(file.GetAsText()) == Error.Ok)
							{
								dirAccess.ListDirEnd();
								return json.Data.AsGodotDictionary();
							}
						}
					}
				}
				fileName = dirAccess.GetNext();
			}
			dirAccess.ListDirEnd();
		}

		var otherFolder = $"{dir}Other/";
		if (DirAccess.DirExistsAbsolute(otherFolder))
		{
			var dirAccess = DirAccess.Open(otherFolder);
			if (dirAccess != null)
			{
				dirAccess.ListDirBegin();
				string fileName = dirAccess.GetNext();
				while (fileName != "")
				{
					if (fileName.EndsWith($"_slot{slot}.json"))
					{
						var filePath = otherFolder + fileName;
						if (FileAccess.FileExists(filePath))
						{
							using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
							if (file != null)
							{
								var json = new Json();
								if (json.Parse(file.GetAsText()) == Error.Ok)
								{
									dirAccess.ListDirEnd();
									return json.Data.AsGodotDictionary();
								}
							}
						}
					}
					fileName = dirAccess.GetNext();
				}
				dirAccess.ListDirEnd();
			}
		}

		return new Dictionary();
	}

	public Godot.Collections.Array<string> GetSlotNames()
	{
		var names   = new Godot.Collections.Array<string>();
		var dir     = _charactersDirOverride ?? CHARACTERS_DIR;
		var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

		for (int slot = 0; slot < SLOT_COUNT; slot++)
		{
			string found = "";
			foreach (char letter in letters)
			{
				var folderPath = $"{dir}{letter}/";
				if (!DirAccess.DirExistsAbsolute(folderPath)) continue;
				var dirAccess = DirAccess.Open(folderPath);
				if (dirAccess == null) continue;
				dirAccess.ListDirBegin();
				string fileName = dirAccess.GetNext();
				while (fileName != "")
				{
					if (fileName.EndsWith($"_slot{slot}.json"))
					{
						found = $"Slot {slot + 1}: {fileName.Replace($"_slot{slot}.json", "").Replace("_", " ")}";
						dirAccess.ListDirEnd();
						goto NextSlot;
					}
					fileName = dirAccess.GetNext();
				}
				dirAccess.ListDirEnd();
			}

			var otherFolder = $"{dir}Other/";
			if (DirAccess.DirExistsAbsolute(otherFolder))
			{
				var dirAccess = DirAccess.Open(otherFolder);
				if (dirAccess != null)
				{
					dirAccess.ListDirBegin();
					string fileName = dirAccess.GetNext();
					while (fileName != "")
					{
						if (fileName.EndsWith($"_slot{slot}.json"))
						{
							found = $"Slot {slot + 1}: {fileName.Replace($"_slot{slot}.json", "").Replace("_", " ")}";
							dirAccess.ListDirEnd();
							goto NextSlot;
						}
						fileName = dirAccess.GetNext();
					}
					dirAccess.ListDirEnd();
				}
			}

			NextSlot:
			names.Add(string.IsNullOrEmpty(found) ? $"Slot {slot + 1}: [Empty]" : found);
		}

		return names;
	}

	public void SaveSlot(int slot, Dictionary characterData)
	{
		var data = characterData.Duplicate();
		data["_slot"] = slot;
		var name = data.ContainsKey("name") ? data["name"].ToString() : "Unnamed";
		if (string.IsNullOrEmpty(name)) name = "Unnamed";
		var firstLetter = name.Substring(0, 1).ToUpper();
		if (firstLetter.Length == 0 || !char.IsLetter(firstLetter[0])) firstLetter = "Other";
		SaveCharacter(firstLetter, slot, data);
	}

	public void SaveCharacter(string letter, int slot, Dictionary characterData)
	{
		var dir        = _charactersDirOverride ?? CHARACTERS_DIR;
		var folderPath = $"{dir}{letter}/";
		if (!DirAccess.DirExistsAbsolute(folderPath))
			DirAccess.MakeDirRecursiveAbsolute(folderPath);

		var name = characterData.ContainsKey("name") ? characterData["name"].ToString() : "Unnamed";
		if (string.IsNullOrEmpty(name)) name = "Unnamed";
		var sanitizedName = name.Replace(" ", "_").Replace("/", "_").Replace("\\", "_");
		var fileName      = $"{sanitizedName}_slot{slot}.json";
		var filePath      = folderPath + fileName;

		var dirAccess = DirAccess.Open(folderPath);
		if (dirAccess != null)
		{
			dirAccess.ListDirBegin();
			string file      = dirAccess.GetNext();
			var toDelete     = new System.Collections.Generic.List<string>();
			while (file != "")
			{
				if (file.EndsWith($"_slot{slot}.json") && file != fileName)
					toDelete.Add(folderPath + file);
				file = dirAccess.GetNext();
			}
			dirAccess.ListDirEnd();
			foreach (var old in toDelete)
				DirAccess.RemoveAbsolute(old);
		}

		using var saveFile = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
		saveFile?.StoreString(Json.Stringify(characterData));
	}

	public Dictionary load_player_prefs()
	{
		var prefsPath = (_charactersDirOverride ?? CHARACTERS_DIR) + "player_prefs.json";
		if (FileAccess.FileExists(prefsPath))
		{
			using var file = FileAccess.Open(prefsPath, FileAccess.ModeFlags.Read);
			if (file != null)
			{
				var json = new Json();
				if (json.Parse(file.GetAsText()) == Error.Ok)
					return json.Data.AsGodotDictionary();
			}
		}
		return new Dictionary();
	}

	public void save_player_prefs(Dictionary prefs)
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		if (!DirAccess.DirExistsAbsolute(dir))
			DirAccess.MakeDirRecursiveAbsolute(dir);
		var prefsPath = dir + "player_prefs.json";
		using var file = FileAccess.Open(prefsPath, FileAccess.ModeFlags.Write);
		file?.StoreString(Json.Stringify(prefs));
	}

	private System.Collections.Generic.IEnumerable<string> GetWorldChildNames(Node world)
	{
		var names = new System.Collections.Generic.List<string>();
		for (int i = 0; i < world.GetChildCount(); i++)
			names.Add(world.GetChild(i).Name);
		return names;
	}

	// ─── GS-Nebula Hub Integration ───────────────────────────────────────────────
	//
	// Called at the end of _Ready(). Reads command-line arguments injected by the
	// GS-Nebula Electron launcher and acts on them:
	//
	//   --auth-token <jwt>           → stores HubAuthToken for dedicated server auth handshakes
	//   --discord-tag <tag>          → stores the player's Discord tag for lobby registration
	//   --join-server <ip>:<port>    → connects to the target server automatically
	//
	// The actual server join is deferred one frame so that all autoloads (including
	// DedicatedServer) have finished their own _Ready() calls.

	// Token passed from GS-Nebula hub via --auth-token argument.
	public string HubAuthToken { get; private set; } = "";

	private void ParseHubArguments()
	{
		var args = OS.GetCmdlineArgs();
		GD.Print($"[GameManager] ParseHubArguments: {args.Length} arg(s) received from hub.");

		for (int i = 0; i < args.Length; i++)
		{
			// ── Auth token ──────────────────────────────────────────────────────
			if (args[i] == "--auth-token" && i + 1 < args.Length)
			{
				HubAuthToken = args[i + 1];
				GD.Print("[GameManager] Hub auth token received and stored.");
				i++;
				continue;
			}

            // ── Host mode ───────────────────────────────────────────────────────
            if (args[i] == "--host")
            {
                GD.Print("[GameManager] Hub requesting local host mode.");
                CallDeferred(MethodName.StartLocalLobby);
                continue;
            }

            // ── Override port for hosting ────────────────────────────────────────
            if (args[i] == "--port" && i + 1 < args.Length)
            {
                if (int.TryParse(args[i + 1], out int overridePort))
                {
                    DefaultPort = overridePort;
                    GD.Print($"[GameManager] Port override from hub: {DefaultPort}");
                }
                i++;
                continue;
            }

            // ── Server name override ─────────────────────────────────────────────
            if (args[i] == "--server-name" && i + 1 < args.Length)
            {
                ServerName = args[i + 1];
                GD.Print($"[GameManager] Server name override: {ServerName}");
                i++;
                continue;
            }

			// ── Discord tag ─────────────────────────────────────────────────────
			if (args[i] == "--discord-tag" && i + 1 < args.Length)
			{
				_hubDiscordTag = args[i + 1];
				GD.Print($"[GameManager] Hub discord tag received: '{_hubDiscordTag}'.");
				i++;
				continue;
			}

			// ── Auto-join server ─────────────────────────────────────────────────
			if (args[i] == "--join-server" && i + 1 < args.Length)
			{
				var raw   = args[i + 1];
				var parts = raw.Split(':');
				if (parts.Length == 2 && int.TryParse(parts[1], out int port))
				{
					var ip = parts[0];
					GD.Print($"[GameManager] Hub requesting auto-join → {ip}:{port}");
					CallDeferred(MethodName.JoinServerFromHub, ip, port);
				}
				else
				{
					GD.PrintErr($"[GameManager] --join-server value malformed: '{raw}' (expected ip:port)");
				}
				i++;
				continue;
			}
		}
	}

	private void JoinServerFromHub(string ip, int port)
	{
		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] JoinServerFromHub: port {port} out of valid range.");
			return;
		}

		GD.Print($"[GameManager] JoinServerFromHub: connecting to {ip}:{port} …");

		var peer = new ENetMultiplayerPeer();
		var err  = peer.CreateClient(ip, port, ENET_CHANNEL_COUNT);

		if (err != Error.Ok)
		{
			GD.PrintErr($"[GameManager] JoinServerFromHub: CreateClient failed — {err}");
			EmitSignal(SignalName.ConnectionFailed);
			return;
		}

		Multiplayer.MultiplayerPeer = peer;
		_peer        = peer;
		_isConnected = false;
		GD.Print("[GameManager] JoinServerFromHub: ENet client peer assigned, awaiting connection confirmation.");
	}

	// ─── End Hub Integration ─────────────────────────────────────────────────────

	public override void _ExitTree()
	{
		LeaveGame();
	}
}
