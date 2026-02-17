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
	private System.Collections.Generic.Dictionary<int, long> _connectionAttempts = new();
	private System.Collections.Generic.Dictionary<int, System.Collections.Generic.List<long>> _messageTimestamps = new();
	private System.Collections.Generic.HashSet<int> _lateJoiners = new();
	private System.Collections.Generic.Dictionary<int, (Vector2 position, string job, Dictionary charData, string nodeName)> _roundParticipants = new();
	private System.Collections.Generic.Dictionary<int, int> _peerToAccount = new();
	private System.Collections.Generic.Dictionary<int, int> _accountToPeer = new();
	private const int MAX_MESSAGES_PER_10_SECONDS = 10;
	private const int MAX_MESSAGE_LENGTH = 200;
	private const int MESSAGE_COOLDOWN_MS = 500;
	private const float CHAT_PROXIMITY_RANGE = 500.0f;
	private const int MIN_NETWORK_PORT = 1024;
	private const int MAX_NETWORK_PORT = 65535;
	private const string CommunicationsScenePath = "res://Scenes/UI/Communications.tscn";
	private const string MainLobbyScenePath = "res://Scenes/UI/MainLobbyUI.tscn";

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

	private const string CharactersDir = "user://characters/";
	private string _charactersDirOverride = null;

	public bool IsHost => _isHosting;
	public GameState CurrentGameState => _currentGameState;
	public bool IsGameRunning() => _gameStarted;
	public bool IsRoundInProgress() => _roundInProgress;
	public int GetCurrentGameState() => (int)_currentGameState;

	public override void _Ready()
	{
		PlayerScene = GD.Load<PackedScene>("uid://cj25bsb3ooj62");
		Multiplayer.PeerConnected += OnPeerConnected;
		Multiplayer.PeerDisconnected += OnPeerDisconnected;
		Multiplayer.ConnectedToServer += OnConnectedToServer;
		Multiplayer.ConnectionFailed += OnConnectionFailed;
		Multiplayer.ServerDisconnected += OnServerDisconnected;
		
		var args = OS.GetCmdlineArgs();
		for (int i = 0; i < args.Length; i++)
		{
			if (args[i] == "--profile" && i + 1 < args.Length)
			{
				_charactersDirOverride = $"user://characters_{args[i + 1]}/";
				GD.Print($"[GameManager] Using profile directory: {_charactersDirOverride}");
				break;
			}
		}
		
		EnsureCharactersDirectory();
		
		_lobbyManager = GetNodeOrNull<LobbyManager>("/root/LobbyManager");
		
		InitializeLateJoinSystem();
		
		var discord = GetNodeOrNull<Node>("/root/DiscordRpc");
		
		GameStateChanged += (stateInt) => {
			if (discord == null) return;
			var state = (GameState)stateInt;
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

	public void SetChatInputActive(bool active)
	{
		ChatInputActive = active;
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

	private void EnsureCharactersDirectory()
	{
		var dir = _charactersDirOverride ?? CharactersDir;
		if (!DirAccess.DirExistsAbsolute(dir))
			DirAccess.MakeDirRecursiveAbsolute(dir);
	}

	public void HostGame(int port = -1)
	{
		if (port == -1) port = DefaultPort;
		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid host port: {port}. Expected {MIN_NETWORK_PORT}-{MAX_NETWORK_PORT}");
			return;
		}
		
		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateServer(port, MaxPlayers);
		
		if (error == Error.Ok)
		{
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
			
			if (!playerData.ContainsKey("peer_id"))
				playerData["peer_id"] = 1;
			_peerCharacters[1] = playerData;
			
			if (prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", 1, playerData);
		}
		else
		{
			GD.PrintErr("[GameManager] PreferenceManager not found, using default player data");
			_playerNames[1] = "Host";
			_peerCharacters[1] = new Dictionary { { "name", "Host" }, { "peer_id", 1 } };
		}

		var hostAccountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
		int hostAccountId = hostAccountManager?.GetUserId() ?? 0;
		if (hostAccountId > 0)
		{
			_peerToAccount[1] = hostAccountId;
			_accountToPeer[hostAccountId] = 1;
		}
			
			SetupLobbyTimer();
			RegisterWithLobby(port);
			EmitSignal(SignalName.PlayerCountChanged, PlayerCount);

			SetGameState(GameState.Lobby);
			GetTree().ChangeSceneToFile(CommunicationsScenePath);
		}
		else
		{
			GD.PrintErr($"Failed to create server: {error}");
		}
	}

	private void RegisterWithLobby(int port)
	{
		if (_lobbyManager == null) return;
		
		var serverInfo = new Dictionary
		{
			{ "name", string.IsNullOrEmpty(ServerName) ? "GodotStation Server" : ServerName },
			{ "description", ServerDescription },
			{ "password_protected", PasswordProtected },
			{ "map", CurrentMap },
			{ "gamemode", Gamemode },
			{ "max_players", MaxPlayers },
			{ "current_players", PlayerCount },
			{ "port", port }
		};
		
		_lobbyManager.Call("RegisterServer", serverInfo);
	}

	private void SetupLobbyTimer()
	{
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
			Multiplayer.MultiplayerPeer = _peer;
			_isConnected = true;
			SetGameState(GameState.Lobby);
			GetTree().ChangeSceneToFile(CommunicationsScenePath);
		}
		else
		{
			GD.PrintErr($"Failed to join game: {error}");
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	public void LeaveGame()
	{
		if (_lobbyManager != null)
		{
			_lobbyManager.Call("UnregisterServer");
		}
		
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped())
		{
			_lobbyTimer.Stop();
		}
		
		if (_peer != null)
		{
			_peer.Close();
		}
		
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
		_peerToAccount.Clear();
		_accountToPeer.Clear();
		PlayerCount = 0;
		
		SetGameState(GameState.Menu);
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

	public void StartGame()
	{
		if (_gameStarted) return;
		
		_gameStarted = true;
		_roundInProgress = true;
		
		if (_lobbyTimer != null)
		{
			_lobbyTimer.Stop();
			_lobbyTimer.QueueFree();
			_lobbyTimer = null;
		}
		
		if (_lobbyUpdateTimer != null)
		{
			_lobbyUpdateTimer.Stop();
			_lobbyUpdateTimer.QueueFree();
			_lobbyUpdateTimer = null;
		}
		
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.SyncRoundState, true);
		}
		
		SetGameState(GameState.Playing);
		EmitSignal(SignalName.GameStarted);
		
		GD.Print("[GameManager] Game round started - late join enabled");
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncRoundState(bool inProgress)
	{
		_roundInProgress = inProgress;
		if (!inProgress)
		{
			_roundParticipants.Clear();
			EmitSignal(SignalName.RoundEnded);
		}
	}

	public void EndRound()
	{
		if (!Multiplayer.IsServer()) return;
		if (!_roundInProgress) return;

		_roundInProgress = false;
		_gameStarted = false;
		_roundParticipants.Clear();

		Rpc(MethodName.SyncRoundState, false);
		SetGameState(GameState.Lobby);

		GD.Print("[GameManager] Round ended");
	}

	private void OnPeerConnected(long id)
	{
		var peerId = (int)id;
		GD.Print($"[GameManager] Player {peerId} connected");
		
		_connectedPeers.Add(peerId);
		PlayerCount = _connectedPeers.Count;
		
		if (Multiplayer.IsServer())
		{
			RpcId(peerId, MethodName.SyncStatusInfo, 
				CurrentMap, Gamemode, PlayerCount, 
				CurrentMusicName, LobbyTimeLeft, LobbyTimerPaused);
			
			if (_roundInProgress)
				RpcId(peerId, MethodName.SyncRoundState, true);
		}
		
		EmitSignal(SignalName.PlayerJoined, peerId);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}
	
	public void ReconnectRoundParticipant(int peerId, int accountId)
	{
		if (!_roundParticipants.ContainsKey(accountId))
			return;

		var (savedPos, savedJob, savedData, oldName) = _roundParticipants[accountId];

		var world = GetTree().GetFirstNodeInGroup("World");
		var oldNode = world?.GetNodeOrNull<Node2D>(oldName);
		oldNode?.QueueFree();

		_peerCharacters[peerId] = savedData;

		SpawnPlayer(peerId, savedPos, savedJob);

		_roundParticipants[accountId] = (savedPos, savedJob, savedData, peerId.ToString());
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void NotifyLateJoiner()
	{
		GD.Print($"[GameManager] Received late joiner notification for peer {Multiplayer.GetUniqueId()}");
		ShowLateJoinUI();
	}
	
	private void ShowLateJoinUI()
	{
		var communications = GetTree().GetFirstNodeInGroup("Communications");
		if (communications == null)
			communications = GetNodeOrNull<Node>("/root/Communications");
		
		if (communications != null && communications.HasMethod("show_late_join_ui"))
			communications.Call("show_late_join_ui");
		else
			GD.PrintErr("[GameManager] Could not find Communications node to show late join UI");
	}

	private void OnPeerDisconnected(long id)
	{
		var peerId = (int)id;
		_connectedPeers.Remove(peerId);
		_lateJoiners.Remove(peerId);
		PlayerCount = _connectedPeers.Count;

		int accountId = _peerToAccount.ContainsKey(peerId) ? _peerToAccount[peerId] : 0;
		_peerToAccount.Remove(peerId);
		if (accountId > 0) _accountToPeer.Remove(accountId);

		if (_roundInProgress && accountId > 0 && _roundParticipants.ContainsKey(accountId))
		{
			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			if (playerNode != null)
			{
				var savedPos = playerNode.GlobalPosition;
				var savedJob = _roundParticipants[accountId].job;
				var savedData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : _roundParticipants[accountId].charData;

				_roundParticipants[accountId] = (savedPos, savedJob, savedData, peerId.ToString());

				playerNode.Set("disconnected_peer", true);

				var inputNode = playerNode.GetNodeOrNull("InputComponent") 
								?? playerNode.GetNodeOrNull("PlayerInput") 
								?? playerNode.GetNodeOrNull("InputHandler");

				if (inputNode != null) inputNode.ProcessMode = ProcessModeEnum.Disabled;

				var stateSystem = playerNode.GetNodeOrNull<MobStateSystem>("MobStateSystem");
				stateSystem?.SetState(MobState.Sleeping);
			}
		}
		else
		{
			if (_jobManager != null && _jobManager.GetAssignedJob(peerId) != "")
				_jobManager.UnassignPeer(peerId);

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
		GD.Print("[GameManager] Successfully connected to server");
		_isConnected = true;
		
		var peerId = Multiplayer.GetUniqueId();
		_connectedPeers.Add(peerId);
		
		var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
		int accountId = accountManager?.GetUserId() ?? 0;

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var playerData = (Dictionary)prefManager.Call("get_character_data");
			RpcId(1, MethodName.RegisterPlayer, peerId, accountId, playerData);
		}
		
		RpcId(1, MethodName.RequestCurrentVideo);
	}

	private void OnConnectionFailed()
	{
		GD.PrintErr("[GameManager] Connection to server failed");
		EmitSignal(SignalName.ConnectionFailed);
		_isConnected = false;
		Multiplayer.MultiplayerPeer = null;
	}

	private void OnServerDisconnected()
	{
		GD.Print("[GameManager] Disconnected from server");
		_isConnected = false;
		_gameStarted = false;
		_roundInProgress = false;
		_connectedPeers.Clear();
		_playerNames.Clear();
		_peerCharacters.Clear();
		_lateJoiners.Clear();
		_roundParticipants.Clear();
		_peerToAccount.Clear();
		_accountToPeer.Clear();
		PlayerCount = 0;
		
		Multiplayer.MultiplayerPeer = null;
		SetGameState(GameState.Menu);
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RegisterPlayer(int peerId, int accountId, Dictionary characterData)
	{
		if (!Multiplayer.IsServer()) return;

		if (accountId > 0)
		{
			_peerToAccount[peerId] = accountId;
			_accountToPeer[accountId] = peerId;
		}

		if (_roundInProgress && accountId > 0 && _roundParticipants.ContainsKey(accountId))
		{
			ReconnectRoundParticipant(peerId, accountId);
			var reconnectName = _playerNames.ContainsKey(peerId) ? _playerNames[peerId] : $"Player{peerId}";
			var reconnectData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
			Rpc(MethodName.BroadcastPlayerJoinedWithData, peerId, reconnectName, reconnectData);
			EmitSignal(SignalName.PlayersUpdated);
			return;
		}

		if (_roundInProgress)
		{
			var playerName = characterData.ContainsKey("name") ? (string)characterData["name"] : $"Player{peerId}";
			_playerNames[peerId] = playerName;

			if (!characterData.ContainsKey("peer_id"))
				characterData["peer_id"] = peerId;
			_peerCharacters[peerId] = characterData;

			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", peerId, characterData);

			_lateJoiners.Add(peerId);
			RpcId(peerId, MethodName.NotifyLateJoiner);
			Rpc(MethodName.BroadcastPlayerJoined, peerId, playerName);
			EmitSignal(SignalName.PlayersUpdated);
			return;
		}

		var name = characterData.ContainsKey("name") ? (string)characterData["name"] : $"Player{peerId}";
		_playerNames[peerId] = name;

		if (!characterData.ContainsKey("peer_id"))
			characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;

		var pref = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (pref != null && pref.HasMethod("set_peer_character_data"))
			pref.Call("set_peer_character_data", peerId, characterData);

		RpcId(peerId, MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		Rpc(MethodName.BroadcastPlayerJoined, peerId, name);
		EmitSignal(SignalName.PlayersUpdated);
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
			if (!charData.ContainsKey("peer_id"))
				charData["peer_id"] = peerId;
			_peerCharacters[peerId] = charData;

			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", peerId, charData);
		}
	}

	public void SendChatMessage(string message, string mode = "IC")
	{
		var peerId = Multiplayer.GetUniqueId();
		
		if (!ValidateMessageRateLimit(peerId))
		{
			GD.PrintErr("[GameManager] Message rate limit exceeded");
			return;
		}
		
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
		if (!ValidateMessageRateLimit(peerId))
		{
			GD.PrintErr("[GameManager] Message rate limit exceeded");
			return;
		}
		
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
			GD.PrintErr($"[GameManager] RPC sender ID mismatch: claimed {claimedSenderId}, actual {actualSenderId}");
			return false;
		}
		return true;
	}

	private bool ValidateMessageRateLimit(int peerId)
	{
		if (!_messageTimestamps.ContainsKey(peerId))
		{
			_messageTimestamps[peerId] = new System.Collections.Generic.List<long>();
		}
		
		var currentTime = (long)Time.GetTicksMsec();
		var timestamps = _messageTimestamps[peerId];
		
		timestamps.RemoveAll(t => currentTime - t > 10000L);
		
		if (timestamps.Count >= MAX_MESSAGES_PER_10_SECONDS)
		{
			return false;
		}
		
		if (timestamps.Count > 0 && currentTime - timestamps[^1] < (long)MESSAGE_COOLDOWN_MS)
		{
			return false;
		}
		
		timestamps.Add(currentTime);
		return true;
	}

	public void SyncMedia(string type, string path, int loops = 1, float volume = 0.5f)
	{
		if (!Multiplayer.IsServer()) return;
		
		CurrentMediaType = type;
		CurrentMediaPath = path;
		CurrentMediaLoops = loops;
		CurrentMediaVolume = volume;
		
		if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
		{
			CurrentMusicName = System.IO.Path.GetFileName(path);
		}
		
		Rpc(MethodName.ReceiveMediaSync, type, path, loops, volume);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveMediaSync(string type, string path, int loops, float volume)
	{
		CurrentMediaType = type;
		CurrentMediaPath = path;
		CurrentMediaLoops = loops;
		CurrentMediaVolume = volume;
		if (string.Equals(type, "music", StringComparison.OrdinalIgnoreCase))
		{
			CurrentMusicName = System.IO.Path.GetFileName(path);
		}
		EmitSignal(SignalName.MediaSyncReceived, type, path, loops, volume);
	}

	public void ToggleLobbyPause()
	{
		if (!Multiplayer.IsServer()) return;
		if (_lobbyTimer == null) return;
		LobbyTimerPaused = !LobbyTimerPaused;
		_lobbyTimer.Paused = LobbyTimerPaused;
		Rpc(MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
	}

	public void ForceStartFromLobby()
	{
		if (!Multiplayer.IsServer()) return;
		if (_gameStarted) return;
		StartGame();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestCurrentVideo()
	{
		if (!Multiplayer.IsServer()) return;
		var requesterId = Multiplayer.GetRemoteSenderId();
		if (requesterId <= 0) return;
		if (!string.IsNullOrEmpty(CurrentVideoUid))
		{
			RpcId(requesterId, MethodName.ReceiveVideoSync, CurrentVideoUid, 0.0f);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveVideoSync(string videoUid, float positionSeconds)
	{
		CurrentVideoUid = videoUid;
		if (!string.IsNullOrEmpty(videoUid))
			EmitSignal(SignalName.MediaSyncReceived, "video", videoUid, 0, 0.5f);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncStatusInfo(string mapName, string gamemode, int currentPlayers, string musicName = "", float timeLeft = -1.0f, bool paused = false)
	{
		if (!string.IsNullOrEmpty(mapName))
			CurrentMap = mapName;
		if (!string.IsNullOrEmpty(gamemode))
			Gamemode = gamemode;
		PlayerCount = currentPlayers;
		if (!string.IsNullOrEmpty(musicName))
			CurrentMusicName = musicName;
		if (timeLeft >= 0.0f)
			LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLobbyState(float timeLeft, bool paused, string videoUid)
	{
		LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		CurrentVideoUid = videoUid;
		EmitSignal(SignalName.LobbyStateSynced, timeLeft, paused, videoUid);
	}

	public const string CHARACTERS_DIR = "user://characters/";
	public const int SLOT_COUNT = 10;

	public Dictionary LoadSlot(int slot)
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
		
		foreach (char letter in letters)
		{
			var folderPath = $"{dir}{letter}/";
			if (!DirAccess.DirExistsAbsolute(folderPath))
				continue;
				
			var dirAccess = DirAccess.Open(folderPath);
			if (dirAccess == null)
				continue;
				
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
							var jsonString = file.GetAsText();
							var json = new Json();
							if (json.Parse(jsonString) == Error.Ok)
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
								var jsonString = file.GetAsText();
								var json = new Json();
								if (json.Parse(jsonString) == Error.Ok)
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
						var charName = fileName.Replace($"_slot{slot}.json", "").Replace("_", " ");
						found = $"Slot {slot + 1}: {charName}";
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
							var charName = fileName.Replace($"_slot{slot}.json", "").Replace("_", " ");
							found = $"Slot {slot + 1}: {charName}";
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
		if (string.IsNullOrEmpty(name))
			name = "Unnamed";
			
		var firstLetter = name.Substring(0, 1).ToUpper();
		if (firstLetter.Length == 0 || !char.IsLetter(firstLetter[0]))
			firstLetter = "Other";
			
		SaveCharacter(firstLetter, slot, data);
	}

	public void SaveCharacter(string letter, int slot, Dictionary characterData)
	{
		var dir = _charactersDirOverride ?? CHARACTERS_DIR;
		var folderPath = $"{dir}{letter}/";
		
		if (!DirAccess.DirExistsAbsolute(folderPath))
			DirAccess.MakeDirRecursiveAbsolute(folderPath);
		
		var name = characterData.ContainsKey("name") ? characterData["name"].ToString() : "Unnamed";
		if (string.IsNullOrEmpty(name))
			name = "Unnamed";
			
		var sanitizedName = name.Replace(" ", "_").Replace("/", "_").Replace("\\", "_");
		var fileName = $"{sanitizedName}_slot{slot}.json";
		var filePath = folderPath + fileName;
		
		var existingFiles = new System.Collections.Generic.List<string>();
		var dirAccess = DirAccess.Open(folderPath);
		if (dirAccess != null)
		{
			dirAccess.ListDirBegin();
			string file = dirAccess.GetNext();
			while (file != "")
			{
				if (file.EndsWith($"_slot{slot}.json") && file != fileName)
					existingFiles.Add(folderPath + file);
				file = dirAccess.GetNext();
			}
			dirAccess.ListDirEnd();
		}
		
		foreach (var oldFile in existingFiles)
		{
			DirAccess.RemoveAbsolute(oldFile);
		}
		
		using var saveFile = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
		if (saveFile != null)
		{
			var jsonString = Json.Stringify(characterData);
			saveFile.StoreString(jsonString);
			GD.Print($"[GameManager] Character saved to {filePath}");
		}
	}

	public Dictionary load_player_prefs()
	{
		var prefsPath = (_charactersDirOverride ?? CHARACTERS_DIR) + "player_prefs.json";
		
		if (FileAccess.FileExists(prefsPath))
		{
			using var file = FileAccess.Open(prefsPath, FileAccess.ModeFlags.Read);
			if (file != null)
			{
				var jsonString = file.GetAsText();
				var json = new Json();
				if (json.Parse(jsonString) == Error.Ok)
				{
					return json.Data.AsGodotDictionary();
				}
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
		if (file != null)
		{
			var jsonString = Json.Stringify(prefs);
			file.StoreString(jsonString);
		}
	}
	
	public void SpawnPlayer(int peerId, Vector2 position, string jobName)
	{
		if (!Multiplayer.IsServer()) return;

		var world = GetTree().GetFirstNodeInGroup("World");
		if (world == null) return;

		var existing = world.GetNodeOrNull<Node2D>(peerId.ToString());
		if (existing != null)
		{
			existing.SetMultiplayerAuthority(peerId);
			existing.ProcessMode = ProcessModeEnum.Inherit;
			var stateSystem = existing.GetNodeOrNull<MobStateSystem>("MobStateSystem");
			stateSystem?.SetState(MobState.Standing);

			int accountId = _peerToAccount.ContainsKey(peerId) ? _peerToAccount[peerId] : 0;
			if (accountId > 0 && _roundParticipants.ContainsKey(accountId))
				_roundParticipants[accountId] = (existing.GlobalPosition, jobName, _peerCharacters[peerId], peerId.ToString());

			RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, existing.GlobalPosition, jobName, _peerCharacters[peerId]);
			return;
		}

		var playerInstance = PlayerScene.Instantiate<Node2D>();
		playerInstance.Name = peerId.ToString();

		var characterData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
		characterData["job"] = jobName;
		if (!characterData.ContainsKey("peer_id"))
			characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;

		if (playerInstance.HasMethod("ApplyCharacterData"))
			playerInstance.Call("ApplyCharacterData", characterData);
		else if (playerInstance.Get("character_data").VariantType != Variant.Type.Nil)
			playerInstance.Set("character_data", characterData);

		world.CallDeferred("add_child", playerInstance);
		playerInstance.Set("global_position", position);

		int accId = _peerToAccount.ContainsKey(peerId) ? _peerToAccount[peerId] : 0;
		if (accId > 0)
			_roundParticipants[accId] = (position, jobName, characterData, peerId.ToString());

		if (peerId == Multiplayer.GetUniqueId())
			ClientSpawnConfirmed(peerId, position, jobName, characterData);
		else
			RpcId(peerId, MethodName.ClientSpawnConfirmed, peerId, position, jobName, characterData);

		if (_lateJoiners.Contains(peerId))
			_lateJoiners.Remove(peerId);

		GD.Print($"[GameManager] Spawned player {peerId} as {jobName} at {position}");
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientSpawnConfirmed(int peerId, Vector2 position, string jobName, Dictionary charData)
	{
		GD.Print($"[GameManager] Client spawn confirmed: {peerId} as {jobName}");

		if (charData != null && charData.Count > 0 && peerId == Multiplayer.GetUniqueId())
		{
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("set_peer_character_data"))
				prefManager.Call("set_peer_character_data", peerId, charData);

			var world = GetTree().GetFirstNodeInGroup("World");
			var playerNode = world?.GetNodeOrNull<Node2D>(peerId.ToString());
			if (playerNode != null && playerNode.HasMethod("ApplyCharacterData"))
				playerNode.Call("ApplyCharacterData", charData);
		}

		EmitSignal(SignalName.LateJoinerTransitioned, peerId);
	}
	
	public void BecomeObserver(int peerId)
	{
		if (!Multiplayer.IsServer()) return;
		
		var observer = new Node2D();
		observer.Name = $"Observer_{peerId}";
		
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world != null)
		{
			world.CallDeferred("add_child", observer);
		}
		
		RpcId(peerId, MethodName.ClientBecomeObserver);
		
		if (_lateJoiners.Contains(peerId))
		{
			_lateJoiners.Remove(peerId);
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientBecomeObserver()
	{
		GD.Print("[GameManager] Became observer");
	}
	
	public Dictionary GetPeerCharacterDataWithJob(int peerId)
	{
		if (_peerCharacters.ContainsKey(peerId))
		{
			var data = _peerCharacters[peerId].Duplicate();
			if (_jobManager != null)
			{
				var job = _jobManager.GetAssignedJob(peerId);
				if (!string.IsNullOrEmpty(job))
					data["job"] = job;
			}
			return data;
		}
		return new Dictionary();
	}
	
	public Dictionary GetPeerCharacterData(int peerId)
	{
		if (_peerCharacters.ContainsKey(peerId))
		{
			return _peerCharacters[peerId].Duplicate();
		}
		return new Dictionary();
	}
	
	public void SetPeerCharacterData(int peerId, Dictionary characterData)
	{
		if (_roundInProgress)
		{
			int accountId = _peerToAccount.ContainsKey(peerId) ? _peerToAccount[peerId] : 0;
			if (accountId > 0 && _roundParticipants.ContainsKey(accountId))
			{
				GD.Print($"[GameManager] Blocked character data change for round participant peer {peerId}");
				return;
			}
		}

		if (!characterData.ContainsKey("peer_id"))
			characterData["peer_id"] = peerId;
		_peerCharacters[peerId] = characterData;
		
		if (characterData.ContainsKey("name"))
		{
			var name = characterData["name"].ToString();
			if (!string.IsNullOrEmpty(name))
				_playerNames[peerId] = name;
		}
	}
	
	public Dictionary get_peer_character_data(int peerId)
	{
		return GetPeerCharacterData(peerId);
	}
	
	public void set_peer_character_data(int peerId, Dictionary characterData)
	{
		SetPeerCharacterData(peerId, characterData);
	}
	
	public void SyncPlayerTransform(int playerId, Vector2 position, float rotation)
	{
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.ReceivePlayerTransform, playerId, position, rotation);
		}
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
		if (world != null)
		{
			var player = world.GetNodeOrNull<Node2D>(playerId.ToString());
			if (player != null)
			{
				player.GlobalPosition = position;
				player.Rotation = rotation;
			}
		}
	}
	
	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIngameTime(float time)
	{
		IngameTime = time;
	}
	
	public void BackToLobby()
	{
		LeaveGame();
	}
	
	public bool IsLateJoiner(int peerId)
	{
		return _lateJoiners.Contains(peerId);
	}

	public override void _ExitTree()
	{
		LeaveGame();
	}
}