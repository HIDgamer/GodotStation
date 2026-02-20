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

	private const int MAX_MESSAGES_PER_10_SECONDS = 10;
	private const int MESSAGE_COOLDOWN_MS = 500;
	private const float CHAT_PROXIMITY_RANGE = 500.0f;
	private const int MIN_NETWORK_PORT = 1024;
	private const int MAX_NETWORK_PORT = 65535;
	private const string CommunicationsScenePath = "res://Scenes/hub/Communications.tscn";
	private const string MainLobbyScenePath = "res://Scenes/hub/Hub.tscn";

	private LobbyManager _lobbyManager;
	private JobManager _jobManager;
	private bool _isHosting = false;
	private bool _isConnected = false;

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
	public GameState CurrentGameState => _currentGameState;
	public bool IsGameRunning() => _gameStarted;
	public bool IsRoundInProgress() => _roundInProgress;
	public int GetCurrentGameState() => (int)_currentGameState;

	public override void _Ready()
	{
		GD.Print("[GameManager] _Ready called.");

		PlayerScene = GD.Load<PackedScene>("uid://cj25bsb3ooj62");
		if (PlayerScene == null)
			GD.PrintErr("[GameManager] CRITICAL: PlayerScene failed to load from uid://cj25bsb3ooj62");
		else
			GD.Print("[GameManager] PlayerScene loaded successfully.");

		Multiplayer.PeerConnected += OnPeerConnected;
		Multiplayer.PeerDisconnected += OnPeerDisconnected;
		Multiplayer.ConnectedToServer += OnConnectedToServer;
		Multiplayer.ConnectionFailed += OnConnectionFailed;
		Multiplayer.ServerDisconnected += OnServerDisconnected;
		GD.Print("[GameManager] Multiplayer signal handlers registered.");

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
		GD.Print($"[GameManager] Characters directory: {_charactersDirOverride ?? CHARACTERS_DIR}");

		_lobbyManager = GetNodeOrNull<LobbyManager>("/root/LobbyManager");
		GD.Print(_lobbyManager != null
			? "[GameManager] LobbyManager found."
			: "[GameManager] WARNING: LobbyManager not found at /root/LobbyManager.");

		InitializeLateJoinSystem();

		var discord = GetNodeOrNull<Node>("/root/DiscordRpc");
		GD.Print(discord != null
			? "[GameManager] DiscordRpc found, state change hook active."
			: "[GameManager] WARNING: DiscordRpc not found, rich presence disabled.");

		GameStateChanged += (stateInt) =>
		{
			var state = (GameState)stateInt;
			GD.Print($"[GameManager] Game state changed to: {state}");
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

		GD.Print("[GameManager] _Ready complete.");
	}

	private void InitializeLateJoinSystem()
	{
		_jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
		if (_jobManager == null)
		{
			GD.Print("[GameManager] JobManager not found, creating a new one.");
			_jobManager = new JobManager();
			_jobManager.Name = "JobManager";
			GetTree().Root.CallDeferred("add_child", _jobManager);
		}
		else
		{
			GD.Print("[GameManager] JobManager found at /root/JobManager.");
		}
	}

	public void SetGameState(GameState newState)
	{
		if (_currentGameState != newState)
		{
			GD.Print($"[GameManager] SetGameState: {_currentGameState} -> {newState}");
			_currentGameState = newState;
			EmitSignal(SignalName.GameStateChanged, (int)newState);
		}
	}

	public void SetChatInputActive(bool active) => ChatInputActive = active;

	public void SendBuildAction(int senderPeerId, string action, Dictionary data)
	{
		GD.Print($"[GameManager] SendBuildAction: peer={senderPeerId} action={action} isServer={Multiplayer.IsServer()}");
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
		GD.Print($"[GameManager] SendBuildActionRpc: relaying action={action} from peer={senderPeerId}");
		BroadcastBuildAction(senderPeerId, action, data);
		Rpc(MethodName.BroadcastBuildAction, senderPeerId, action, data);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastBuildAction(int peerId, string action, Dictionary data)
	{
		EmitSignal(SignalName.BuildActionReceived, peerId, action, data);
	}

	private void EnsureCharactersDirectory()
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		if (!DirAccess.DirExistsAbsolute(dir))
		{
			DirAccess.MakeDirRecursiveAbsolute(dir);
			GD.Print($"[GameManager] Created characters directory: {dir}");
		}
	}

	public void HostGame(int port = -1)
	{
		if (port == -1) port = DefaultPort;
		GD.Print($"[GameManager] HostGame called: port={port} maxPlayers={MaxPlayers} serverName='{ServerName}'");

		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid host port: {port}. Expected {MIN_NETWORK_PORT}-{MAX_NETWORK_PORT}");
			return;
		}

		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateServer(port, MaxPlayers);

		if (error != Error.Ok)
		{
			GD.PrintErr($"[GameManager] Failed to create server on port {port}: {error}");
			return;
		}

		GD.Print($"[GameManager] Server created successfully on port {port}.");
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
			GD.Print($"[GameManager] Host character registered: name='{hostName}'");
		}
		else
		{
			GD.PrintErr("[GameManager] PreferenceManager not found, using default host character data.");
			_playerNames[1] = "Host";
			_peerCharacters[1] = new Dictionary { { "name", "Host" }, { "peer_id", 1 } };
		}

		var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
		var hostTag = accountManager?.GetDiscordTag() ?? "";
		if (!string.IsNullOrEmpty(hostTag))
		{
			_peerToDiscordTag[1] = hostTag;
			_discordTagToPeer[hostTag] = 1;
			GD.Print($"[GameManager] Host Discord tag registered: '{hostTag}' -> peer 1");
		}
		else
		{
			GD.PrintErr("[GameManager] WARNING: Host has no Discord tag. Reconnect identity will not work for host.");
		}

		SetupLobbyTimer();
		RegisterWithLobby(port);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		SetGameState(GameState.Lobby);
		GD.Print("[GameManager] HostGame complete, changing scene to Communications.");
		GetTree().ChangeSceneToFile(CommunicationsScenePath);
	}

	private void RegisterWithLobby(int port)
	{
		if (_lobbyManager == null)
		{
			GD.Print("[GameManager] RegisterWithLobby skipped: no LobbyManager.");
			return;
		}
		GD.Print($"[GameManager] Registering server with LobbyManager: name='{ServerName}' port={port}");
		_lobbyManager.Call("RegisterServer", new Dictionary
		{
			{ "name", string.IsNullOrEmpty(ServerName) ? "GodotStation Server" : ServerName },
			{ "description", ServerDescription },
			{ "password_protected", PasswordProtected },
			{ "map", CurrentMap },
			{ "gamemode", Gamemode },
			{ "max_players", MaxPlayers },
			{ "current_players", PlayerCount },
			{ "port", port }
		});
	}

	private void SetupLobbyTimer()
	{
		GD.Print($"[GameManager] SetupLobbyTimer: duration={LobbyTimeLeft}s");
		_lobbyTimer = new Timer();
		_lobbyTimer.WaitTime = LobbyTimeLeft;
		_lobbyTimer.OneShot = true;
		_lobbyTimer.Timeout += OnLobbyTimerTimeout;
		AddChild(_lobbyTimer);
		_lobbyTimer.Start();

		_lobbyUpdateTimer = new Timer();
		_lobbyUpdateTimer.WaitTime = 1.0f;
		_lobbyUpdateTimer.Timeout += OnLobbyUpdateTimeout;
		AddChild(_lobbyUpdateTimer);
		_lobbyUpdateTimer.Start();
	}

	private void OnLobbyTimerTimeout()
	{
		GD.Print("[GameManager] Lobby timer expired, starting game.");
		EmitSignal(SignalName.LobbyTimeout);
		StartGame();
	}

	private void OnLobbyUpdateTimeout()
	{
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped())
		{
			LobbyTimeLeft = (float)_lobbyTimer.TimeLeft;
			EmitSignal(SignalName.PlayersUpdated);
		}
	}

	public void JoinGame(string address, int port)
	{
		GD.Print($"[GameManager] JoinGame called: address='{address}' port={port}");

		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid join port: {port}. Expected {MIN_NETWORK_PORT}-{MAX_NETWORK_PORT}");
			EmitSignal(SignalName.ConnectionFailed);
			return;
		}

		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateClient(address, port);

		if (error == Error.Ok)
		{
			GD.Print($"[GameManager] ENet client created, connecting to {address}:{port}...");
			Multiplayer.MultiplayerPeer = _peer;
			_isConnected = true;
			SetGameState(GameState.Lobby);
			GetTree().ChangeSceneToFile(CommunicationsScenePath);
		}
		else
		{
			GD.PrintErr($"[GameManager] Failed to create ENet client for {address}:{port}: {error}");
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	public void LeaveGame()
	{
		GD.Print($"[GameManager] LeaveGame called. isHosting={_isHosting} isConnected={_isConnected} gameStarted={_gameStarted}");
		_lobbyManager?.Call("UnregisterServer");
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
		SetGameState(GameState.Menu);
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

	public void StartGame()
	{
		GD.Print($"[GameManager] StartGame called. gameStarted={_gameStarted} isServer={Multiplayer.IsServer()}");

		if (_gameStarted)
		{
			GD.Print("[GameManager] StartGame aborted: game already started.");
			return;
		}

		_gameStarted = true;
		_roundInProgress = true;
		GD.Print($"[GameManager] Round started. Participants at round start: {_roundParticipants.Count}");

		if (_lobbyTimer != null) { _lobbyTimer.Stop(); _lobbyTimer.QueueFree(); _lobbyTimer = null; }
		if (_lobbyUpdateTimer != null) { _lobbyUpdateTimer.Stop(); _lobbyUpdateTimer.QueueFree(); _lobbyUpdateTimer = null; }

		if (Multiplayer.IsServer())
		{
			GD.Print("[GameManager] Broadcasting SyncRoundState(true) to all peers.");
			Rpc(MethodName.SyncRoundState, true);
		}

		SetGameState(GameState.Playing);
		EmitSignal(SignalName.GameStarted);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncRoundState(bool inProgress)
	{
		GD.Print($"[GameManager] SyncRoundState received: inProgress={inProgress} (local peer={Multiplayer.GetUniqueId()})");
		_roundInProgress = inProgress;
		if (!inProgress)
		{
			GD.Print($"[GameManager] Round ended. Clearing {_roundParticipants.Count} participants, {_sleepingMobs.Count} sleeping mobs.");
			_roundParticipants.Clear();
			_sleepingMobs.Clear();
			_sleepingMobData.Clear();
			EmitSignal(SignalName.RoundEnded);
		}
	}

	public void EndRound()
	{
		GD.Print($"[GameManager] EndRound called. isServer={Multiplayer.IsServer()} roundInProgress={_roundInProgress}");
		if (!Multiplayer.IsServer() || !_roundInProgress) return;

		_roundInProgress = false;
		_gameStarted = false;
		GD.Print($"[GameManager] Clearing round data: {_roundParticipants.Count} participants, {_sleepingMobs.Count} sleeping mobs.");
		_roundParticipants.Clear();
		_sleepingMobs.Clear();
		_sleepingMobData.Clear();
		Rpc(MethodName.SyncRoundState, false);
		SetGameState(GameState.Lobby);
		GD.Print("[GameManager] EndRound complete.");
	}

	private void OnPeerConnected(long id)
	{
		var peerId = (int)id;
		GD.Print($"[GameManager] OnPeerConnected: peer={peerId} isServer={Multiplayer.IsServer()} totalPeers={_connectedPeers.Count + 1}");

		_connectedPeers.Add(peerId);
		PlayerCount = _connectedPeers.Count;

		if (Multiplayer.IsServer())
		{
			GD.Print($"[GameManager] Sending SyncStatusInfo to new peer {peerId}. roundInProgress={_roundInProgress}");
			RpcId(peerId, MethodName.SyncStatusInfo,
				CurrentMap, Gamemode, PlayerCount,
				CurrentMusicName, LobbyTimeLeft, LobbyTimerPaused);

			if (_roundInProgress)
			{
				GD.Print($"[GameManager] Round in progress, sending SyncRoundState(true) to peer {peerId}.");
				RpcId(peerId, MethodName.SyncRoundState, true);
			}

			// Warm the new peer's _peerCharacters cache with data for all players the server
			// already knows about. This prevents GetPeerCharacterData cache-miss errors when
			// the PlayerJoined signal fires listeners before BroadcastPlayerJoinedWithData arrives.
			foreach (var kvp in _peerCharacters)
			{
				if (kvp.Key == peerId) continue; // their own data comes via RegisterPlayer/WakeUp
				var cachedName = _playerNames.ContainsKey(kvp.Key) ? _playerNames[kvp.Key] : $"Player{kvp.Key}";
				GD.Print($"[GameManager] Pre-seeding peer {peerId} with data for existing peer {kvp.Key} ('{cachedName}').");
				RpcId(peerId, MethodName.BroadcastPlayerJoinedWithData, kvp.Key, cachedName, kvp.Value);
			}
		}

		EmitSignal(SignalName.PlayerJoined, peerId);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		GD.Print($"[GameManager] OnPeerConnected complete. PlayerCount={PlayerCount}");
	}

	private void OnPeerDisconnected(long id)
	{
		var peerId = (int)id;
		GD.Print($"[GameManager] OnPeerDisconnected: peer={peerId} roundInProgress={_roundInProgress}");

		_connectedPeers.Remove(peerId);
		_lateJoiners.Remove(peerId);
		PlayerCount = _connectedPeers.Count;

		var discordTag = _peerToDiscordTag.ContainsKey(peerId) ? _peerToDiscordTag[peerId] : "";
		GD.Print($"[GameManager] Disconnecting peer {peerId} Discord tag: '{(string.IsNullOrEmpty(discordTag) ? "(none)" : discordTag)}'");

		_peerToDiscordTag.Remove(peerId);
		if (!string.IsNullOrEmpty(discordTag)) _discordTagToPeer.Remove(discordTag);

		var isRoundParticipant = _roundInProgress && !string.IsNullOrEmpty(discordTag) && _roundParticipants.Contains(discordTag);
		GD.Print($"[GameManager] Peer {peerId} qualifies as sleeping round participant: {isRoundParticipant}");

		if (isRoundParticipant)
		{
			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());

			if (playerNode == null)
				GD.PrintErr($"[GameManager] WARNING: Could not find player node '{peerId}' in World. Mob will not be put to sleep.");
			else
				GD.Print($"[GameManager] Found player node '{peerId}' at {playerNode.GlobalPosition}. Putting to sleep.");

			var charData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
			if (_jobManager != null)
			{
				var job = _jobManager.GetAssignedJob(peerId);
				if (!string.IsNullOrEmpty(job))
				{
					charData["job"] = job;
					GD.Print($"[GameManager] Saved job '{job}' into sleeping mob data for tag '{discordTag}'.");
				}
				else
				{
					GD.Print($"[GameManager] Peer {peerId} had no job assigned in JobManager at disconnect time.");
				}
			}
			_sleepingMobData[discordTag] = charData;
			GD.Print($"[GameManager] Sleeping mob data stored for tag '{discordTag}'. Keys: [{string.Join(", ", charData.Keys)}]");

			if (playerNode != null)
			{
				var inputNode = playerNode.GetNodeOrNull("InputComponent")
					?? playerNode.GetNodeOrNull("PlayerInput")
					?? playerNode.GetNodeOrNull("InputHandler");
				if (inputNode != null)
				{
					inputNode.ProcessMode = ProcessModeEnum.Disabled;
					GD.Print($"[GameManager] Disabled input node '{inputNode.Name}' on peer {peerId}'s mob.");
				}
				// Note: Mob.cs handles input directly via IsMultiplayerAuthority() so no
				// separate input node exists – MobStateSystem.Sleeping handles the freeze.

				var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
				if (stateSystem != null)
				{
					stateSystem.SetState(MobState.Sleeping);
					GD.Print($"[GameManager] MobStateSystem set to Sleeping for peer {peerId}.");
				}
				else
				{
					GD.PrintErr($"[GameManager] WARNING: MobStateSystem not found on peer {peerId}'s mob.");
				}

				_sleepingMobs[discordTag] = peerId.ToString();
				GD.Print($"[GameManager] Sleeping mob registered: tag='{discordTag}' -> nodeName='{peerId}'");
			}
		}
		else
		{
			GD.Print($"[GameManager] Peer {peerId} was not a round participant, cleaning up normally.");
			if (_jobManager != null && !string.IsNullOrEmpty(_jobManager.GetAssignedJob(peerId)))
			{
				GD.Print($"[GameManager] Unassigning job from JobManager for peer {peerId}.");
				_jobManager.UnassignPeer(peerId);
			}

			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			if (playerNode != null)
			{
				GD.Print($"[GameManager] QueueFree on node '{peerId}' in World.");
				playerNode.QueueFree();
			}
			else
			{
				GD.Print($"[GameManager] No player node found for peer {peerId} in World (may not have spawned yet).");
			}
		}

		_peerCharacters.Remove(peerId);
		_playerNames.Remove(peerId);

		EmitSignal(SignalName.PlayerLeft, peerId);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		GD.Print($"[GameManager] OnPeerDisconnected complete. PlayerCount={PlayerCount} SleepingMobs={_sleepingMobs.Count}");
	}

	private void OnConnectedToServer()
	{
		_isConnected = true;
		var peerId = Multiplayer.GetUniqueId();
		GD.Print($"[GameManager] OnConnectedToServer: assigned peer ID = {peerId}");

		_connectedPeers.Add(peerId);

		var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
		var discordTag = accountManager?.GetDiscordTag() ?? "";

		if (string.IsNullOrEmpty(discordTag))
			GD.PrintErr($"[GameManager] WARNING: Client peer {peerId} has no Discord tag. Reconnect identity will not work.");
		else
			GD.Print($"[GameManager] Client peer {peerId} Discord tag: '{discordTag}'");

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var playerData = (Dictionary)prefManager.Call("get_character_data");
			var charName = playerData.ContainsKey("name") ? (string)playerData["name"] : "(unknown)";
			GD.Print($"[GameManager] Sending RegisterPlayer RPC to server. peer={peerId} tag='{discordTag}' name='{charName}'");
			RpcId(1, MethodName.RegisterPlayer, peerId, discordTag, playerData);
		}
		else
		{
			GD.PrintErr("[GameManager] WARNING: PreferenceManager not found, RegisterPlayer RPC not sent.");
		}

		RpcId(1, MethodName.RequestCurrentVideo);
		GD.Print("[GameManager] OnConnectedToServer complete.");
	}

	private void OnConnectionFailed()
	{
		GD.PrintErr("[GameManager] OnConnectionFailed: connection to server failed.");
		EmitSignal(SignalName.ConnectionFailed);
		_isConnected = false;
		Multiplayer.MultiplayerPeer = null;
	}

	private void OnServerDisconnected()
	{
		GD.PrintErr("[GameManager] OnServerDisconnected: lost connection to server. Clearing all state.");
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
		PlayerCount = 0;
		Multiplayer.MultiplayerPeer = null;
		SetGameState(GameState.Menu);
		GD.Print("[GameManager] State cleared after server disconnect. Returning to main lobby.");
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RegisterPlayer(int peerId, string discordTag, Dictionary characterData)
	{
		if (!Multiplayer.IsServer()) return;

		var charName = characterData.ContainsKey("name") ? (string)characterData["name"] : "(unknown)";
		GD.Print($"[GameManager] RegisterPlayer: peer={peerId} tag='{discordTag}' name='{charName}' roundInProgress={_roundInProgress}");

		if (!string.IsNullOrEmpty(discordTag))
		{
			if (_discordTagToPeer.TryGetValue(discordTag, out var stalePeer) && stalePeer != peerId)
			{
				GD.Print($"[GameManager] Stale peer mapping found for tag '{discordTag}': old={stalePeer}, new={peerId}. Replacing.");
				// Only evict the old peer's reverse-mapping if that peer is genuinely gone.
				// If the peer is still connected (e.g. host == peer 1 in a local test), keep its entry
				// so SpawnPlayer can still find its Discord tag.
				if (!_connectedPeers.Contains(stalePeer))
					_peerToDiscordTag.Remove(stalePeer);
				else
					GD.Print($"[GameManager] Old peer {stalePeer} is still connected – keeping its _peerToDiscordTag entry.");
			}
			_peerToDiscordTag[peerId] = discordTag;
			_discordTagToPeer[discordTag] = peerId;
			GD.Print($"[GameManager] Discord tag mapped: '{discordTag}' -> peer {peerId}");
		}
		else
		{
			GD.PrintErr($"[GameManager] WARNING: RegisterPlayer called with empty Discord tag for peer {peerId}. Reconnect will not work.");
		}

		if (_roundInProgress && !string.IsNullOrEmpty(discordTag) && _sleepingMobs.ContainsKey(discordTag))
		{
			GD.Print($"[GameManager] Sleeping mob found for tag '{discordTag}'. Waking up for peer {peerId}.");
			WakeUpReturningPlayer(peerId, discordTag, characterData);
			return;
		}

		if (_roundInProgress)
		{
			GD.Print($"[GameManager] Peer {peerId} tag '{discordTag}' not in sleeping mobs. isInRoundParticipants={_roundParticipants.Contains(discordTag)}");
			GD.Print($"[GameManager] Sleeping mobs registry: [{string.Join(", ", _sleepingMobs.Keys)}]");
			GD.Print($"[GameManager] Round participants registry: [{string.Join(", ", _roundParticipants)}]");
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
			GD.Print($"[GameManager] Peer {peerId} is a new late joiner. Sending NotifyLateJoiner.");
			_lateJoiners.Add(peerId);
			RpcId(peerId, MethodName.NotifyLateJoiner);
			Rpc(MethodName.BroadcastPlayerJoined, peerId, playerName);
			EmitSignal(SignalName.PlayersUpdated);
			return;
		}

		GD.Print($"[GameManager] Peer {peerId} joining in lobby. Syncing lobby state.");
		RpcId(peerId, MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		Rpc(MethodName.BroadcastPlayerJoined, peerId, playerName);
		EmitSignal(SignalName.PlayersUpdated);
		GD.Print($"[GameManager] RegisterPlayer complete for peer {peerId}.");
	}

	private void WakeUpReturningPlayer(int newPeerId, string discordTag, Dictionary incomingData)
	{
		GD.Print($"[GameManager] WakeUpReturningPlayer: newPeer={newPeerId} tag='{discordTag}'");

		var sleepingNodeName = _sleepingMobs[discordTag];
		_sleepingMobs.Remove(discordTag);
		GD.Print($"[GameManager] Sleeping node name for tag '{discordTag}': '{sleepingNodeName}'");

		var hasSavedData = _sleepingMobData.ContainsKey(discordTag);
		var savedData = hasSavedData ? _sleepingMobData[discordTag] : incomingData;
		_sleepingMobData.Remove(discordTag);

		GD.Print($"[GameManager] Using {(hasSavedData ? "server-saved" : "incoming client")} character data. Keys: [{string.Join(", ", savedData.Keys)}]");
		if (savedData.ContainsKey("job"))
			GD.Print($"[GameManager] Job in saved data: '{savedData["job"]}'");
		else
			GD.PrintErr("[GameManager] WARNING: No 'job' key in saved data for reconnecting player.");

		savedData["peer_id"] = newPeerId;
		_peerCharacters[newPeerId] = savedData;
		// Also keep data under the old node name (oldPeerId) so any system that looks up
		// character data by the current node name still finds something while the
		// ClientRenamePlayerNode RPC is in flight.  It will be cleaned up once the
		// rename is applied and the old key is no longer meaningful.
		if (int.TryParse(sleepingNodeName, out var oldPeerIdForAlias) && oldPeerIdForAlias != newPeerId)
			_peerCharacters[oldPeerIdForAlias] = savedData;
		if (savedData.ContainsKey("name"))
		{
			_playerNames[newPeerId] = (string)savedData["name"];
			GD.Print($"[GameManager] Player name for peer {newPeerId}: '{_playerNames[newPeerId]}'");
		}

		var pref = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (pref != null && pref.HasMethod("set_peer_character_data"))
			pref.Call("set_peer_character_data", newPeerId, savedData);

		if (int.TryParse(sleepingNodeName, out var oldPeerId) && oldPeerId != newPeerId && _jobManager != null)
		{
			var job = _jobManager.GetAssignedJob(oldPeerId);
			if (!string.IsNullOrEmpty(job))
			{
				GD.Print($"[GameManager] Transferring job '{job}' in JobManager: peer {oldPeerId} -> peer {newPeerId}");
				_jobManager.UnassignPeer(oldPeerId);
				_jobManager.AssignJob(newPeerId, job);
			}
			else
			{
				GD.Print($"[GameManager] Old peer {oldPeerId} had no active job in JobManager (may have been cleared at disconnect).");
			}
		}
		else if (!int.TryParse(sleepingNodeName, out _))
		{
			GD.PrintErr($"[GameManager] WARNING: Could not parse peer ID from sleeping node name '{sleepingNodeName}'.");
		}

		GD.Print($"[GameManager] Scheduling ApplyReconnectDeferred for peer {newPeerId} / node '{sleepingNodeName}'.");
		CallDeferred(MethodName.ApplyReconnectDeferred, newPeerId, sleepingNodeName, savedData);
	}

	private void ApplyReconnectDeferred(int newPeerId, string sleepingNodeName, Dictionary savedData)
	{
		GD.Print($"[GameManager] ApplyReconnectDeferred executing: newPeer={newPeerId} sleepingNode='{sleepingNodeName}'");

		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null)
		{
			GD.PrintErr($"[GameManager] CRITICAL: World group not found in ApplyReconnectDeferred for peer {newPeerId}. Falling back to late join.");
			FallbackToLateJoin(newPeerId);
			return;
		}

		var playerNode = world.GetNodeOrNull<Node2D>(sleepingNodeName);
		if (playerNode == null || !IsInstanceValid(playerNode))
		{
			GD.PrintErr($"[GameManager] Sleeping node '{sleepingNodeName}' not found or invalid. Falling back to late join for peer {newPeerId}.");
			GD.Print($"[GameManager] World children at fallback time: [{string.Join(", ", GetWorldChildNames(world))}]");
			FallbackToLateJoin(newPeerId);
			return;
		}

		GD.Print($"[GameManager] Found sleeping node '{sleepingNodeName}' at position {playerNode.GlobalPosition}. Renaming to '{newPeerId}'.");
		playerNode.Name = newPeerId.ToString();
		playerNode.SetMultiplayerAuthority(newPeerId);
		GD.Print($"[GameManager] Node renamed and authority assigned to peer {newPeerId}.");

		// Now that the old alias is cleaned up, remove it.
		if (int.TryParse(sleepingNodeName, out var oldAliasId) && oldAliasId != newPeerId)
			_peerCharacters.Remove(oldAliasId);

		// Re-sync any active pull relationship so the reconnecting client knows it is
		// being pulled (or is pulling someone), and all other clients get updated NodePaths.
		var reconnectedInteraction = playerNode.GetNodeOrNull<Node>("PlayerInteractionSystem");
		if (reconnectedInteraction != null && reconnectedInteraction.HasMethod("ResyncPullStateAfterRename"))
		{
			GD.Print($"[GameManager] Resyncing pull state for reconnected peer {newPeerId}.");
			reconnectedInteraction.Call("ResyncPullStateAfterRename", newPeerId);
		}

		var inputNode = playerNode.GetNodeOrNull("InputComponent")
			?? playerNode.GetNodeOrNull("PlayerInput")
			?? playerNode.GetNodeOrNull("InputHandler");
		if (inputNode != null)
		{
			inputNode.ProcessMode = ProcessModeEnum.Inherit;
			GD.Print($"[GameManager] Re-enabled input node '{inputNode.Name}' on peer {newPeerId}'s mob.");
		}
		// Note: Mob.cs handles input via IsMultiplayerAuthority() – no separate input node exists.

		var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		if (stateSystem != null)
		{
			stateSystem.SetState(MobState.Standing);
			GD.Print($"[GameManager] MobStateSystem set to Standing for peer {newPeerId}.");
		}
		else
		{
			GD.PrintErr($"[GameManager] WARNING: MobStateSystem not found on reconnected mob for peer {newPeerId}.");
		}

		GD.Print($"[GameManager] Broadcasting ClientRenamePlayerNode: '{sleepingNodeName}' -> {newPeerId}");
		Rpc(MethodName.ClientRenamePlayerNode, sleepingNodeName, newPeerId);

		var broadcastName = _playerNames.ContainsKey(newPeerId) ? _playerNames[newPeerId] : $"Player{newPeerId}";
		GD.Print($"[GameManager] Broadcasting BroadcastPlayerJoinedWithData: peer={newPeerId} name='{broadcastName}'");
		Rpc(MethodName.BroadcastPlayerJoinedWithData, newPeerId, broadcastName, savedData);
		EmitSignal(SignalName.PlayersUpdated);

		GD.Print($"[GameManager] Scheduling ClientReconnectConfirmed for peer {newPeerId} in 0.35s.");
		// Capture position NOW before the client gains authority and starts sending
		// movement updates that would interpolate the server node away from this spot.
		var spawnPosition = playerNode.GlobalPosition;
		GD.Print($"[GameManager] Captured authoritative spawn position: {spawnPosition}");
		var confirmTimer = GetTree().CreateTimer(0.35);
		confirmTimer.Timeout += () =>
		{
			if (IsInstanceValid(playerNode))
			{
				GD.Print($"[GameManager] Timer fired: sending ClientReconnectConfirmed to peer {newPeerId} at {spawnPosition}.");
				RpcId(newPeerId, MethodName.ClientReconnectConfirmed, newPeerId, spawnPosition, savedData);
			}
			else
			{
				GD.PrintErr($"[GameManager] WARNING: Player node for peer {newPeerId} became invalid before ClientReconnectConfirmed timer fired.");
			}
		};
	}

	private void FallbackToLateJoin(int peerId)
	{
		GD.Print($"[GameManager] FallbackToLateJoin: peer={peerId}");
		_lateJoiners.Add(peerId);
		RpcId(peerId, MethodName.NotifyLateJoiner);
		var name = _playerNames.ContainsKey(peerId) ? _playerNames[peerId] : $"Player{peerId}";
		Rpc(MethodName.BroadcastPlayerJoined, peerId, name);
		EmitSignal(SignalName.PlayersUpdated);
	}

	private System.Collections.Generic.IEnumerable<string> GetWorldChildNames(Node world)
	{
		var names = new System.Collections.Generic.List<string>();
		for (int i = 0; i < world.GetChildCount(); i++)
			names.Add(world.GetChild(i).Name);
		return names;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientRenamePlayerNode(string oldName, int newPeerId)
	{
		GD.Print($"[GameManager] ClientRenamePlayerNode: '{oldName}' -> '{newPeerId}' (localPeer={Multiplayer.GetUniqueId()})");
		var world = GetTree().GetFirstNodeInGroup("World");
		var playerNode = world?.GetNodeOrNull<Node2D>(oldName);
		if (playerNode != null && IsInstanceValid(playerNode))
		{
			playerNode.Name = newPeerId.ToString();
			// Set authority immediately on the client side so IsMultiplayerAuthority()
			// is correct for the 0.35s window before ClientReconnectConfirmed arrives.
			// Without this the reconnecting client's mob stays non-authoritative and
			// the camera/input remain disabled.
			playerNode.SetMultiplayerAuthority(newPeerId);
			GD.Print($"[GameManager] Node rename applied on this client: '{oldName}' -> '{newPeerId}'. Authority set to {newPeerId}.");
		}
		else
		{
			GD.PrintErr($"[GameManager] ClientRenamePlayerNode: node '{oldName}' not found in World on peer {Multiplayer.GetUniqueId()}.");
			var w = GetTree().GetFirstNodeInGroup("World");
			if (w != null) GD.Print($"[GameManager] World children: [{string.Join(", ", GetWorldChildNames(w))}]");
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientReconnectConfirmed(int peerId, Vector2 position, Dictionary charData)
	{
		GD.Print($"[GameManager] ClientReconnectConfirmed: targetPeer={peerId} localPeer={Multiplayer.GetUniqueId()} position={position}");

		if (peerId != Multiplayer.GetUniqueId())
		{
			GD.Print($"[GameManager] ClientReconnectConfirmed not for us, ignoring.");
			return;
		}

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
		{
			prefManager.Call("set_peer_character_data", peerId, charData);
			GD.Print($"[GameManager] PreferenceManager updated with reconnected character data for peer {peerId}.");
		}

		var world = GetTree().GetFirstNodeInGroup("World");
		var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());

		if (playerNode != null)
		{
			GD.Print($"[GameManager] Found local player node '{peerId}' at {playerNode.GlobalPosition}. Applying data and waking.");

			// Snap to the server's authoritative position immediately to avoid
			// NetworkManager's interpolation sliding the character from the wrong spot.
			playerNode.GlobalPosition = position;
			GD.Print($"[GameManager] Local mob warped to server position {position}.");

			// ApplyCharacterData handles appearance, re-evaluates IsMultiplayerAuthority(),
			// re-enables the camera and all IMobSystems.  This is the single call that
			// restores full control to the reconnecting player.
			if (playerNode.HasMethod("ApplyCharacterData"))
			{
				playerNode.Call("ApplyCharacterData", charData);
				GD.Print($"[GameManager] ApplyCharacterData called on local mob for peer {peerId} – camera and input restored.");
			}
			else
			{
				// Fallback: at minimum try to re-assert authority and enable the camera.
				GD.PrintErr($"[GameManager] WARNING: Player node '{peerId}' missing ApplyCharacterData – calling RefreshAuthority as fallback.");
				if (playerNode.HasMethod("RefreshAuthority"))
					playerNode.Call("RefreshAuthority");
			}

			var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			if (stateSystem != null)
			{
				stateSystem.SetState(MobState.Standing);
				GD.Print($"[GameManager] Local mob set to Standing for peer {peerId}.");
			}
			else
			{
				GD.PrintErr($"[GameManager] WARNING: MobStateSystem not found on local mob for peer {peerId}.");
			}
		}
		else
		{
			GD.PrintErr($"[GameManager] CRITICAL: ClientReconnectConfirmed could not find player node '{peerId}' in World.");
			if (world != null) GD.Print($"[GameManager] World children: [{string.Join(", ", GetWorldChildNames(world))}]");
		}

		GD.Print($"[GameManager] Emitting LateJoinerTransitioned for peer {peerId}.");
		EmitSignal(SignalName.LateJoinerTransitioned, peerId);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void NotifyLateJoiner()
	{
		GD.Print($"[GameManager] NotifyLateJoiner received on peer {Multiplayer.GetUniqueId()}. Showing late join UI.");
		ShowLateJoinUI();
	}

	private void ShowLateJoinUI()
	{
		var communications = GetTree().GetFirstNodeInGroup("Communications")
			?? GetNodeOrNull<Node>("/root/Communications");
		if (communications != null && communications.HasMethod("show_late_join_ui"))
		{
			GD.Print("[GameManager] Calling show_late_join_ui on Communications.");
			communications.Call("show_late_join_ui");
		}
		else
		{
			GD.PrintErr("[GameManager] Could not find Communications node to show late join UI.");
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastPlayerJoined(int peerId, string playerName)
	{
		GD.Print($"[GameManager] BroadcastPlayerJoined: peer={peerId} name='{playerName}'");
		_playerNames[peerId] = playerName;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastPlayerJoinedWithData(int peerId, string playerName, Dictionary charData)
	{
		GD.Print($"[GameManager] BroadcastPlayerJoinedWithData: peer={peerId} name='{playerName}' dataKeys=[{string.Join(", ", charData?.Keys ?? new Godot.Collections.Array())}]");
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
		var timestamps = _messageTimestamps[peerId];
		timestamps.RemoveAll(t => currentTime - t > 10000L);

		if (timestamps.Count >= MAX_MESSAGES_PER_10_SECONDS)
		{
			GD.PrintErr($"[GameManager] Rate limit exceeded for peer {peerId}: {timestamps.Count} msgs in last 10s.");
			return false;
		}
		if (timestamps.Count > 0 && currentTime - timestamps[^1] < MESSAGE_COOLDOWN_MS)
		{
			GD.PrintErr($"[GameManager] Message cooldown not elapsed for peer {peerId}: {currentTime - timestamps[^1]}ms since last.");
			return false;
		}

		timestamps.Add(currentTime);
		return true;
	}

	public void SyncMedia(string type, string path, int loops = 1, float volume = 0.5f)
	{
		if (!Multiplayer.IsServer()) return;
		GD.Print($"[GameManager] SyncMedia: type={type} path='{path}' loops={loops} volume={volume}");
		CurrentMediaType = type;
		CurrentMediaPath = path;
		CurrentMediaLoops = loops;
		CurrentMediaVolume = volume;
		if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
			CurrentMusicName = System.IO.Path.GetFileName(path);
		Rpc(MethodName.ReceiveMediaSync, type, path, loops, volume);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveMediaSync(string type, string path, int loops, float volume)
	{
		GD.Print($"[GameManager] ReceiveMediaSync: type={type} path='{path}'");
		CurrentMediaType = type;
		CurrentMediaPath = path;
		CurrentMediaLoops = loops;
		CurrentMediaVolume = volume;
		if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
			CurrentMusicName = System.IO.Path.GetFileName(path);
		EmitSignal(SignalName.MediaSyncReceived, type, path, loops, volume);
	}

	public void ToggleLobbyPause()
	{
		if (!Multiplayer.IsServer() || _lobbyTimer == null) return;
		LobbyTimerPaused = !LobbyTimerPaused;
		GD.Print($"[GameManager] ToggleLobbyPause: paused={LobbyTimerPaused}");
		_lobbyTimer.Paused = LobbyTimerPaused;
		Rpc(MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
	}

	public void ForceStartFromLobby()
	{
		GD.Print($"[GameManager] ForceStartFromLobby: isServer={Multiplayer.IsServer()} gameStarted={_gameStarted}");
		if (!Multiplayer.IsServer() || _gameStarted) return;
		StartGame();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestCurrentVideo()
	{
		if (!Multiplayer.IsServer()) return;
		var requesterId = Multiplayer.GetRemoteSenderId();
		GD.Print($"[GameManager] RequestCurrentVideo from peer {requesterId}. CurrentVideoUid='{CurrentVideoUid}'");
		if (requesterId > 0 && !string.IsNullOrEmpty(CurrentVideoUid))
			RpcId(requesterId, MethodName.ReceiveVideoSync, CurrentVideoUid, 0.0f);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveVideoSync(string videoUid, float positionSeconds)
	{
		GD.Print($"[GameManager] ReceiveVideoSync: uid='{videoUid}' pos={positionSeconds}s");
		CurrentVideoUid = videoUid;
		if (!string.IsNullOrEmpty(videoUid))
			EmitSignal(SignalName.MediaSyncReceived, "video", videoUid, 0, 0.5f);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStatusInfo(string mapName, string gamemode, int currentPlayers, string musicName = "", float timeLeft = -1.0f, bool paused = false)
	{
		GD.Print($"[GameManager] SyncStatusInfo: map='{mapName}' mode='{gamemode}' players={currentPlayers} music='{musicName}' timeLeft={timeLeft} paused={paused}");
		if (!string.IsNullOrEmpty(mapName)) CurrentMap = mapName;
		if (!string.IsNullOrEmpty(gamemode)) Gamemode = gamemode;
		PlayerCount = currentPlayers;
		if (!string.IsNullOrEmpty(musicName)) CurrentMusicName = musicName;
		if (timeLeft >= 0.0f) LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLobbyState(float timeLeft, bool paused, string videoUid)
	{
		GD.Print($"[GameManager] SyncLobbyState: timeLeft={timeLeft} paused={paused} videoUid='{videoUid}'");
		LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		CurrentVideoUid = videoUid;
		EmitSignal(SignalName.LobbyStateSynced, timeLeft, paused, videoUid);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIngameTime(float time) => IngameTime = time;

	public void SpawnPlayer(int peerId, Vector2 position, string jobName)
	{
		GD.Print($"[GameManager] SpawnPlayer: peer={peerId} job='{jobName}' position={position} isServer={Multiplayer.IsServer()}");

		if (!Multiplayer.IsServer())
		{
			GD.PrintErr("[GameManager] SpawnPlayer called on non-server. Aborting.");
			return;
		}

		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null)
		{
			GD.PrintErr("[GameManager] SpawnPlayer: World group not found. Aborting.");
			return;
		}

		var existing = world.GetNodeOrNull<Node2D>(peerId.ToString());
		if (existing != null)
		{
			GD.Print($"[GameManager] SpawnPlayer: existing node found for peer {peerId} at {existing.GlobalPosition}. Re-using.");
		// Cancel any deferred ClientSpawnConfirmed timer that was set up for the previous
		// spawn call for this peer – this new reuse-spawn supersedes it.
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

			GD.Print($"[GameManager] Sending ClientSpawnConfirmed (reuse) to peer {peerId}.");
			RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, existing.GlobalPosition, jobName, charData);
			return;
		}

		GD.Print($"[GameManager] SpawnPlayer: instantiating new node for peer {peerId}.");
		var playerInstance = PlayerScene.Instantiate<Node2D>();
		playerInstance.Name = peerId.ToString();

		var characterData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
		characterData["job"] = jobName;
		if (!characterData.ContainsKey("peer_id")) characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;

		if (playerInstance.HasMethod("ApplyCharacterData"))
		{
			playerInstance.Call("ApplyCharacterData", characterData);
			GD.Print($"[GameManager] ApplyCharacterData called on new instance for peer {peerId}.");
		}
		else if (playerInstance.Get("character_data").VariantType != Variant.Type.Nil)
		{
			playerInstance.Set("character_data", characterData);
			GD.Print($"[GameManager] Set character_data property on new instance for peer {peerId}.");
		}
		else
		{
			GD.PrintErr($"[GameManager] WARNING: Player instance for peer {peerId} has neither ApplyCharacterData nor character_data.");
		}

		playerInstance.Position = position;
		playerInstance.SetMultiplayerAuthority(peerId);
		world.CallDeferred("add_child", playerInstance);
		GD.Print($"[GameManager] New node for peer {peerId} deferred-added to World at {position}.");

		var discordTag = _peerToDiscordTag.ContainsKey(peerId) ? _peerToDiscordTag[peerId] : "";
		if (!string.IsNullOrEmpty(discordTag))
		{
			_roundParticipants.Add(discordTag);
			GD.Print($"[GameManager] Peer {peerId} (tag='{discordTag}') added to roundParticipants. Total: {_roundParticipants.Count}");
		}
		else
		{
			GD.PrintErr($"[GameManager] WARNING: No Discord tag for peer {peerId} at spawn time. Reconnect will not be possible.");
		}

		if (peerId == Multiplayer.GetUniqueId())
		{
			// CallDeferred so the queued add_child above has resolved before we search the tree.
			GD.Print($"[GameManager] Spawning self, deferring ClientSpawnConfirmed locally.");
			CallDeferred(MethodName.ClientSpawnConfirmed, peerId, position, jobName, characterData);
		}
		else
		{
			// Give the MultiplayerSpawner one frame to replicate the new node to the client
			// before we tell it to configure itself.
			GD.Print($"[GameManager] Scheduling ClientSpawnConfirmed RPC to peer {peerId} (deferred by one frame).");
			_pendingSpawnConfirm.Add(peerId);
			var capturedPosition = position;
			var capturedJob = jobName;
			var capturedData = characterData;
			var spawnTimer = GetTree().CreateTimer(0.05);
			spawnTimer.Timeout += () =>
			{
				if (IsInstanceValid(this) && _pendingSpawnConfirm.Remove(peerId))
				{
					GD.Print($"[GameManager] Deferred ClientSpawnConfirmed firing for peer {peerId} job='{capturedJob}'.");
					RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, capturedPosition, capturedJob, capturedData);
				}
				else
				{
					GD.Print($"[GameManager] Deferred ClientSpawnConfirmed for peer {peerId} cancelled (superseded by a later spawn).");
				}
			};
		}

		_lateJoiners.Remove(peerId);
		GD.Print($"[GameManager] SpawnPlayer complete for peer {peerId}. LateJoiners remaining: {_lateJoiners.Count}");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientSpawnConfirmed(int peerId, Vector2 position, string jobName, Dictionary charData)
	{
		GD.Print($"[GameManager] ClientSpawnConfirmed: peer={peerId} job='{jobName}' position={position} localPeer={Multiplayer.GetUniqueId()}");

		if (charData != null && charData.Count > 0 && peerId == Multiplayer.GetUniqueId())
		{
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
			{
				prefManager.Call("set_peer_character_data", peerId, charData);
				GD.Print($"[GameManager] PreferenceManager updated with spawn data for local peer {peerId}.");
			}

			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			if (playerNode != null && playerNode.HasMethod("ApplyCharacterData"))
			{
				playerNode.Call("ApplyCharacterData", charData);
				GD.Print($"[GameManager] ApplyCharacterData on local node for peer {peerId}.");
			}
			else if (playerNode == null)
			{
				GD.PrintErr($"[GameManager] WARNING: ClientSpawnConfirmed could not find local node '{peerId}' in World.");
			}
		}

		GD.Print($"[GameManager] Emitting LateJoinerTransitioned for peer {peerId}.");
		EmitSignal(SignalName.LateJoinerTransitioned, peerId);
	}

	public void BecomeObserver(int peerId)
	{
		GD.Print($"[GameManager] BecomeObserver: peer={peerId}");
		if (!Multiplayer.IsServer()) return;
		var observer = new Node2D { Name = $"Observer_{peerId}" };
		GetTree().GetFirstNodeInGroup("World")?.CallDeferred("add_child", observer);
		RpcId(peerId, MethodName.ClientBecomeObserver);
		_lateJoiners.Remove(peerId);
		GD.Print($"[GameManager] Observer node queued for peer {peerId}.");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientBecomeObserver()
	{
		GD.Print($"[GameManager] ClientBecomeObserver received on peer {Multiplayer.GetUniqueId()}.");
	}

	public void SyncPlayerTransform(int playerId, Vector2 position, float rotation)
	{
		if (Multiplayer.IsServer())
			Rpc(MethodName.ReceivePlayerTransform, playerId, position, rotation);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void RequestSyncPlayerTransform(int playerId, Vector2 position, float rotation)
	{
		if (!Multiplayer.IsServer()) return;
		Rpc(MethodName.ReceivePlayerTransform, playerId, position, rotation);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void ReceivePlayerTransform(int playerId, Vector2 position, float rotation)
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		var player = world?.GetNodeOrNull<Node2D>(playerId.ToString());
		if (player != null)
		{
			player.GlobalPosition = position;
			player.Rotation = rotation;
		}
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
		GD.PrintErr($"[GameManager] GetPeerCharacterDataWithJob: no data for peer {peerId}.");
		return new Dictionary();
	}

	public Dictionary GetPeerCharacterData(int peerId)
	{
		if (!_peerCharacters.ContainsKey(peerId))
			GD.Print($"[GameManager] GetPeerCharacterData: no data cached for peer {peerId} yet (may still be arriving).");
		return _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId].Duplicate() : new Dictionary();
	}

	public void SetPeerCharacterData(int peerId, Dictionary characterData)
	{
		GD.Print($"[GameManager] SetPeerCharacterData: peer={peerId} name='{(characterData.ContainsKey("name") ? characterData["name"].ToString() : "(none)")}'");
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

	public Dictionary LoadSlot(int slot)
	{
		GD.Print($"[GameManager] LoadSlot: slot={slot}");
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
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
								GD.Print($"[GameManager] LoadSlot {slot} found: {filePath}");
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
									GD.Print($"[GameManager] LoadSlot {slot} found in Other: {filePath}");
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

		GD.PrintErr($"[GameManager] LoadSlot {slot}: no file found.");
		return new Dictionary();
	}

	public Godot.Collections.Array<string> GetSlotNames()
	{
		var names = new Godot.Collections.Array<string>();
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;

		for (int slot = 0; slot < SLOT_COUNT; slot++)
		{
			string found = "";
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
		GD.Print($"[GameManager] SaveSlot: slot={slot} name='{(characterData.ContainsKey("name") ? characterData["name"].ToString() : "(none)")}'");
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
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		var folderPath = $"{dir}{letter}/";
		if (!DirAccess.DirExistsAbsolute(folderPath))
			DirAccess.MakeDirRecursiveAbsolute(folderPath);

		var name = characterData.ContainsKey("name") ? characterData["name"].ToString() : "Unnamed";
		if (string.IsNullOrEmpty(name)) name = "Unnamed";
		var sanitizedName = name.Replace(" ", "_").Replace("/", "_").Replace("\\", "_");
		var fileName = $"{sanitizedName}_slot{slot}.json";
		var filePath = folderPath + fileName;

		var dirAccess = DirAccess.Open(folderPath);
		if (dirAccess != null)
		{
			dirAccess.ListDirBegin();
			string file = dirAccess.GetNext();
			var toDelete = new System.Collections.Generic.List<string>();
			while (file != "")
			{
				if (file.EndsWith($"_slot{slot}.json") && file != fileName)
					toDelete.Add(folderPath + file);
				file = dirAccess.GetNext();
			}
			dirAccess.ListDirEnd();
			foreach (var old in toDelete)
			{
				GD.Print($"[GameManager] SaveCharacter: removing stale file '{old}'");
				DirAccess.RemoveAbsolute(old);
			}
		}

		using var saveFile = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
		if (saveFile != null)
		{
			saveFile.StoreString(Json.Stringify(characterData));
			GD.Print($"[GameManager] SaveCharacter: saved to '{filePath}'");
		}
		else
		{
			GD.PrintErr($"[GameManager] SaveCharacter: failed to open '{filePath}' for writing.");
		}
	}

	public Dictionary load_player_prefs()
	{
		var prefsPath = (_charactersDirOverride ?? CHARACTERS_DIR) + "player_prefs.json";
		GD.Print($"[GameManager] load_player_prefs: path='{prefsPath}'");
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
		GD.Print("[GameManager] load_player_prefs: file not found, returning empty dict.");
		return new Dictionary();
	}

	public void save_player_prefs(Dictionary prefs)
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		if (!DirAccess.DirExistsAbsolute(dir))
			DirAccess.MakeDirRecursiveAbsolute(dir);
		var prefsPath = dir + "player_prefs.json";
		using var file = FileAccess.Open(prefsPath, FileAccess.ModeFlags.Write);
		if (file != null)
		{
			file.StoreString(Json.Stringify(prefs));
			GD.Print($"[GameManager] save_player_prefs: saved to '{prefsPath}'");
		}
		else
		{
			GD.PrintErr($"[GameManager] save_player_prefs: failed to open '{prefsPath}' for writing.");
		}
	}

	public override void _ExitTree()
	{
		GD.Print("[GameManager] _ExitTree called, running LeaveGame cleanup.");
		LeaveGame();
	}
}
