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
	private System.Collections.Generic.List<int> _connectedPeers = new();
	private System.Collections.Generic.Dictionary<int, string> _playerNames = new();
	private System.Collections.Generic.Dictionary<int, Dictionary> _peerCharacters = new();
	private System.Collections.Generic.Dictionary<int, long> _connectionAttempts = new();
	private System.Collections.Generic.Dictionary<int, System.Collections.Generic.List<long>> _messageTimestamps = new();
	private const int MAX_MESSAGES_PER_10_SECONDS = 10;
	private const int MAX_MESSAGE_LENGTH = 200;
	private const int MESSAGE_COOLDOWN_MS = 500;
	private const float CHAT_PROXIMITY_RANGE = 500.0f;
	private const int MIN_NETWORK_PORT = 1024;
	private const int MAX_NETWORK_PORT = 65535;
	private const string CommunicationsSceneUid = "uid://bjnqqapnkk8uq";
	private const string MainLobbyScenePath = "res://Scenes/UI/MainLobbyUI.tscn";

	private LobbyManager _lobbyManager;
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

	private const string CharactersDir = "user://characters/";
	private string _charactersDirOverride = null;

	public bool IsHost => _isHosting;
	public GameState CurrentGameState => _currentGameState;
	public bool IsGameRunning() => _gameStarted;
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
		
		var discord = GetNode<DiscordRPC>("/root/DiscordRpc");
		
		GameStateChanged += (stateInt) => {
			var state = (GameState)stateInt;
			switch (state)
			{
				case GameState.Lobby:
					discord.SetInLobby();
					break;
				case GameState.Playing:
					discord.SetInGame(ServerName, PlayerCount, MaxPlayers);
					break;
				case GameState.Hosting:
					discord.SetHosting(ServerName, PlayerCount, MaxPlayers);
					break;
			}
		};
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
			prefManager.Call("set_peer_character_data", 1, playerData);
		}
		else
		{
			GD.PrintErr("[GameManager] PreferenceManager not found, using default player data");
			_playerNames[1] = "Host";
			_peerCharacters[1] = new Dictionary { { "name", "Host" }, { "peer_id", 1 } };
		}
			
			SetupLobbyTimer();
			RegisterWithLobby(port);
			EmitSignal(SignalName.PlayerCountChanged, PlayerCount);

			SetGameState(GameState.Lobby);
			GetTree().ChangeSceneToFile(CommunicationsSceneUid);
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
		_lobbyUpdateTimer.Timeout += UpdateLobbyTimer;
		AddChild(_lobbyUpdateTimer);
		_lobbyUpdateTimer.Start();
	}

	private void UpdateLobbyTimer()
	{
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped() && !LobbyTimerPaused)
		{
			LobbyTimeLeft = (float)_lobbyTimer.TimeLeft;
			EmitSignal(SignalName.PlayersUpdated);
		}
	}

	private void OnLobbyTimerTimeout()
	{
		if (_gameStarted) return;
		
		GD.Print("[GameManager] Lobby timer expired");
		EmitSignal(SignalName.LobbyTimeout);
		StartGame();
	}

	public void DelayLobby(float additionalTime = 60.0f)
	{
		if (!Multiplayer.IsServer()) return;
		if (_gameStarted) return;
		
		LobbyTimeLeft += additionalTime;
		LobbyTimerPaused = false;
		
		if (_lobbyTimer != null)
		{
			_lobbyTimer.Stop();
			_lobbyTimer.WaitTime = LobbyTimeLeft;
			_lobbyTimer.Start();
		}
		
		Rpc(MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		GD.Print($"[GameManager] Lobby delayed by {additionalTime} seconds. New time: {LobbyTimeLeft}");
	}

	public async void StartGame()
	{
		if (!Multiplayer.IsServer()) return;
		if (_gameStarted) return;
		
		GD.Print($"[GameManager] StartGame called on server");
		_gameStarted = true;
		LobbyTimerPaused = false;
		
		if (_lobbyTimer != null)
		{
			_lobbyTimer.Stop();
			LobbyTimeLeft = 0;
		}
		
		SetGameState(GameState.Playing);
		EmitSignal(SignalName.GameStarted);
		
		var world = GetWorld();
		if (world != null)
		{
			foreach (var child in world.GetChildren())
			{
				if (int.TryParse(child.Name, out _))
					child.QueueFree();
			}
			
			var spawnPositions = new Vector2[] {
				new(2 * 32, 2 * 32),
				new(3 * 32, 3 * 32),
				new(1 * 32, 3 * 32),
				new(3 * 32, 3 * 32)
			};
			
			var wm = world.GetNodeOrNull("WorldManager");
			if (wm != null)
			{
				foreach (var pos in spawnPositions)
				{
					var cell = new Vector2I(Mathf.FloorToInt(pos.X / 32.0f), Mathf.FloorToInt(pos.Y / 32.0f));
					wm.Call("UpdateTileRpc", cell, "floor");
				}
			}
			
			await ToSignal(GetTree(), "process_frame");
			
			var spawnIndex = 0;
			var SpawnArray = _connectedPeers.ToArray();
			var PlayersReadyNow = SpawnArray.Count();
			var TotalFrames = Mathf.Min(15, PlayersReadyNow);
			var SpawnPerFrame = Mathf.CeilToInt(PlayersReadyNow / (float)TotalFrames);
			var SpawnedThisFrame = 0;
			
			foreach (var peerId in SpawnArray)
			{
				if (peerId > 0)
				{
					var spawnPos = spawnPositions[spawnIndex % spawnPositions.Length];	
					SpawnPlayer(peerId, spawnPos);
					spawnIndex++;
					SpawnedThisFrame++;

					if (SpawnedThisFrame >= SpawnPerFrame)
					{
						SpawnedThisFrame = 0;
						await ToSignal(GetTree(), "process_frame");
					}
				}
			}
		}
		
		Rpc(MethodName.ClientStartGame);
		EmitSignal(SignalName.PlayersUpdated);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
	private void ClientStartGame()
	{
		_gameStarted = true;
		LobbyTimerPaused = false;
		SetGameState(GameState.Playing);
		EmitSignal(SignalName.GameStarted);
	}

	public void JoinGame(string address, int port = -1)
	{
		if (port == -1) port = DefaultPort;
		if (port < MIN_NETWORK_PORT || port > MAX_NETWORK_PORT)
		{
			GD.PrintErr($"[GameManager] Invalid join port: {port}. Expected {MIN_NETWORK_PORT}-{MAX_NETWORK_PORT}");
			return;
		}
		
		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateClient(address, port);
		
		if (error == Error.Ok)
		{
			Multiplayer.MultiplayerPeer = _peer;
			GD.Print($"[GameManager] Connecting to {address}:{port}...");
		}
		else
		{
			GD.PrintErr($"[GameManager] Failed to create client: {error}");
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	private void OnPeerConnected(long id)
	{
		int peerId = (int)id;
		
		if (!ValidateConnectionRate(peerId))
		{
			if (Multiplayer.IsServer())
				_peer.DisconnectPeer(peerId);
			return;
		}
		
		_connectedPeers.Add(peerId);
		PlayerCount = _connectedPeers.Count;
		
		GD.Print($"[GameManager] Peer {id} connected. Total players: {PlayerCount}");
		EmitSignal(SignalName.PlayerJoined, peerId);
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.SyncLobbyState, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
			RpcId(peerId, MethodName.SyncIngameTime, IngameTime);
			
			if (!string.IsNullOrEmpty(CurrentMediaType) && !string.IsNullOrEmpty(CurrentMediaPath))
			{
				RpcId(peerId, MethodName.BroadcastMediaSync, CurrentMediaType, CurrentMediaPath, CurrentMediaLoops, CurrentMediaVolume);
			}
			
			foreach (var kvp in _peerCharacters)
			{
				if (kvp.Key != peerId)
					RpcId(peerId, MethodName.SyncPlayerAppearance, kvp.Key, kvp.Value);
			}
			
			UpdatePlayerCount();
		}
		
		if (_gameStarted && Multiplayer.IsServer())
		{
			GD.Print($"[GameManager] Late joiner {peerId} connected");
			CallDeferred(MethodName.HandleLateJoiner, peerId);
		}
		else if (!Multiplayer.IsServer())
		{
			return;
		}
		else
		{
			CallDeferred(MethodName.SyncNewPeerCharacterData, peerId);
		}
	}

	private void SyncNewPeerCharacterData(int peerId)
	{
		if (!Multiplayer.IsServer()) return;
		
		foreach (var kvp in _peerCharacters)
		{
			if (kvp.Key != peerId)
			{
				RpcId(peerId, MethodName.ReceiveCharacterData, kvp.Key, kvp.Value);
			}
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RegisterCharacterData(int peerId, Dictionary characterData)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(peerId)) return;
		
		_peerCharacters[peerId] = characterData;
		
		if (characterData.ContainsKey("name"))
		{
			_playerNames[peerId] = characterData["name"].ToString();
		}
		
		Rpc(MethodName.ReceiveCharacterData, peerId, characterData);
		GD.Print($"[GameManager] Registered character data for peer {peerId}");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceiveCharacterData(int peerId, Dictionary characterData)
	{
		_peerCharacters[peerId] = characterData;
		
		if (characterData.ContainsKey("name"))
		{
			_playerNames[peerId] = characterData["name"].ToString();
		}
		
		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			prefManager.Call("set_peer_character_data", peerId, characterData);
		}
		
		GD.Print($"[GameManager] Received character data for peer {peerId}");
	}

	public Dictionary GetPeerCharacterData(int peerId)
	{
		return _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
	}

	public void SetPeerCharacterData(int peerId, Dictionary characterData)
	{
		_peerCharacters[peerId] = characterData;
		
		if (characterData.ContainsKey("name"))
		{
			_playerNames[peerId] = characterData["name"].ToString();
		}
		
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.ReceiveCharacterData, peerId, characterData);
		}
		else
		{
			RpcId(1, MethodName.RegisterCharacterData, peerId, characterData);
		}
	}

	public void PushLocalAppearanceUpdate()
	{
		var peerId = Multiplayer.GetUniqueId();
		if (peerId <= 0) peerId = 1;
		
		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var characterData = (Dictionary)prefManager.Call("get_character_data");
			SetPeerCharacterData(peerId, characterData);
		}
	}

	private void HandleLateJoiner(int peerId)
	{
		if (!Multiplayer.IsServer()) return;
		
		GD.Print($"[GameManager] Handling late joiner: {peerId}");
		
		RpcId(peerId, MethodName.TransitionLateJoinerToGame);
		
		var spawnPos = FindSafeSpawnPosition();
		RpcId(peerId, MethodName.ConfirmSpawn, spawnPos);
		
		var characterData = _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : null;
		CallDeferred(MethodName.SpawnPlayerForLateJoiner, peerId, spawnPos, characterData);
		
		RpcId(peerId, MethodName.SendChatMessage, 0, "System", "The round has started, please choose a role and late-join", "IC");
	}

	private async void SpawnPlayerForLateJoiner(int peerId, Vector2 spawnPos, Dictionary characterData)
	{
		await ToSignal(GetTree(), "process_frame");
		await ToSignal(GetTree(), "process_frame");
		
		var world = GetWorld();
		if (world == null)
		{
			GD.PrintErr("[GameManager] World not found for late joiner spawn");
			return;
		}
		
		GD.Print($"[GameManager] Spawning late joiner {peerId} at {spawnPos}");
		SpawnPlayer(peerId, spawnPos, characterData);
		
		await ToSignal(GetTree(), "process_frame");
		SendWorldStateToPlayer(peerId);
	}

	private Vector2 FindSafeSpawnPosition()
	{
		var world = GetWorld();
		if (world == null) return new Vector2(2 * 32, 2 * 32);
		
		var existingPlayers = new System.Collections.Generic.List<Vector2>();
		foreach (var child in world.GetChildren())
		{
			if (child is Node2D node2D && int.TryParse(child.Name, out _))
			{
				existingPlayers.Add(node2D.GlobalPosition);
			}
		}
		
		if (existingPlayers.Count > 0)
		{
			var lastPlayerPos = existingPlayers[existingPlayers.Count - 1];
			return lastPlayerPos + new Vector2(64, 64);
		}
		
		var spawnPositions = new Vector2[] {
			new(2 * 32, 2 * 32),
			new(3 * 32, 3 * 32),
			new(1 * 32, 3 * 32),
			new(3 * 32, 1 * 32)
		};
		
		return spawnPositions[GD.RandRange(0, spawnPositions.Length - 1)];
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ConfirmSpawn(Vector2 position)
	{
		GD.Print($"[GameManager] Late joiner spawned at {position}");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void TransitionLateJoinerToGame()
	{
		GD.Print("[GameManager] Transitioning late joiner to game");
		
		EmitSignal(SignalName.GameStarted);
		
		EmitSignal("LateJoinerTransitioned");
		
		var communications = GetNodeOrNull<Control>("../Communications");
		if (communications != null)
		{
			if (communications.HasMethod("_on_late_joiner_transitioned"))
				communications.Call("_on_late_joiner_transitioned");
		}
	}

	private void SendWorldStateToPlayer(int playerId)
	{
		var world = GetWorld();
		if (world == null) return;
		
		foreach (var child in world.GetChildren())
		{
			if (child is Node2D node2D && int.TryParse(child.Name, out var id) && id != playerId)
			{
				RpcId(playerId, MethodName.SendPlayerState, id, node2D.GlobalPosition, node2D.Rotation);
			}
		}
		
		SendWorldItemsToPlayer(playerId);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendPlayerState(int playerId, Vector2 position, float rotation)
	{
		var world = GetWorld();
		if (world == null) return;
		
		var existingPlayer = world.GetNodeOrNull<Node2D>(playerId.ToString());
		if (existingPlayer != null)
		{
			existingPlayer.GlobalPosition = position;
			existingPlayer.Rotation = rotation;
		}
	}

	private void SendWorldItemsToPlayer(int playerId)
	{
		var world = GetWorld();
		if (world == null) return;
		
		foreach (var child in world.GetChildren())
		{
			if (child is WorldItem worldItem)
			{
				RpcId(playerId, MethodName.SendWorldItem, worldItem.ItemId, worldItem.GlobalPosition, worldItem.Quantity);
			}
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendWorldItem(string itemId, Vector2 position, int quantity)
	{
		var world = GetWorld();
		if (world == null) return;
		
		var worldItemScene = GD.Load<PackedScene>("res://Scenes/WorldItem.tscn");
		if (worldItemScene == null) return;
		
		var worldItem = worldItemScene.Instantiate<WorldItem>();
		worldItem.ItemId = itemId;
		worldItem.GlobalPosition = position;
		worldItem.Quantity = quantity;
		world.AddChild(worldItem);
	}

	private void OnPeerDisconnected(long id)
	{
		int peerId = (int)id;
		GD.Print($"[GameManager] Peer {peerId} disconnected");
		_connectedPeers.Remove(peerId);
		_playerNames.Remove(peerId);
		_peerCharacters.Remove(peerId);
		
		if (Multiplayer.IsServer())
		{
			PlayerCount = Math.Max(1, PlayerCount - 1);
			EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
			EmitSignal(SignalName.PlayersUpdated);
		}
		
		EmitSignal(SignalName.PlayerLeft, peerId);
		
		var world = GetWorld();
		if (world != null)
		{
			var playerNode = world.GetNodeOrNull(peerId.ToString());
			if (playerNode != null)
			{
				playerNode.QueueFree();
				GD.Print($"[GameManager] Removed player node for disconnected peer {peerId}");
			}
		}
	}

	private void OnConnectedToServer()
	{
		int peerId = Multiplayer.GetUniqueId();
		GD.Print($"[GameManager] Connected to server with peer ID: {peerId}");
		_isConnected = true;
		_connectedPeers.Add(peerId);
		
		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			var characterData = (Dictionary)prefManager.Call("get_character_data");
			if (!characterData.ContainsKey("peer_id"))
				characterData["peer_id"] = peerId;
			
			_peerCharacters[peerId] = characterData;
			prefManager.Call("set_peer_character_data", peerId, characterData);
			
			RpcId(1, MethodName.RegisterCharacterData, peerId, characterData);
		}
		
		SetGameState(GameState.Lobby);
	}

	private void OnConnectionFailed()
	{
		GD.PrintErr("[GameManager] Connection to server failed");
		EmitSignal(SignalName.ConnectionFailed);
		_isConnected = false;
		LeaveGame();
	}

	private void OnServerDisconnected()
	{
		GD.Print("[GameManager] Disconnected from server");
		_isConnected = false;
		_gameStarted = false;
		LeaveGame();
		GetTree().ChangeSceneToFile(MainLobbyScenePath);
	}

	public void LeaveGame()
	{
		GD.Print("[GameManager] Leaving game");
		
		if (_lobbyManager != null && _isHosting)
		{
			_lobbyManager.Call("UnregisterServer");
		}
		
		if (_peer != null && _peer.GetConnectionStatus() != MultiplayerPeer.ConnectionStatus.Disconnected)
		{
			_peer.Close();
		}
		
		Multiplayer.MultiplayerPeer = null;
		
		_connectedPeers.Clear();
		_playerNames.Clear();
		_peerCharacters.Clear();
		_gameStarted = false;
		_isHosting = false;
		_isConnected = false;
		PlayerCount = 0;
		
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
		
		SetGameState(GameState.Menu);
		GD.Print("[GameManager] Game left successfully");
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendChatMessage(int senderPeerId, string senderName, string message, string mode = "IC")
	{
		EmitSignal(SignalName.ChatMessageReceived, senderPeerId, senderName, message, mode);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIngameTime(float time)
	{
		IngameTime = time;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPlayerAppearance(int peerId, Dictionary playerData)
	{
		_peerCharacters[peerId] = playerData;
		
		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null)
		{
			prefManager.Call("set_peer_character_data", peerId, playerData);
		}
		
		if (playerData.ContainsKey("name"))
		{
			var playerName = (string)playerData["name"];
			if (!string.IsNullOrEmpty(playerName))
				_playerNames[peerId] = playerName;
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestSendChat(int senderPeerId, string message, string mode = "IC")
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(senderPeerId)) return;
		if (!ValidateChatMessage(senderPeerId, message)) return;
		
		SendChatFromPlayer(senderPeerId, message, mode);
	}

	private bool ValidateRpcSender(int claimedSenderId)
	{
		int actualSenderId = Multiplayer.GetRemoteSenderId();
		
		if (actualSenderId != claimedSenderId)
		{
			GD.PrintErr($"[GameManager] RPC sender mismatch! Claimed: {claimedSenderId}, Actual: {actualSenderId}");
			return false;
		}
		
		return true;
	}

	private bool ValidateChatMessage(int peerId, string message)
	{
		if (string.IsNullOrWhiteSpace(message) || message.Length > MAX_MESSAGE_LENGTH)
			return false;
		
		long currentTime = (long)Time.GetTicksMsec();
		
		if (!_messageTimestamps.ContainsKey(peerId))
			_messageTimestamps[peerId] = new System.Collections.Generic.List<long>();
		
		var timestamps = _messageTimestamps[peerId];
		timestamps.RemoveAll(t => currentTime - t > 10000);
		
		if (timestamps.Count >= MAX_MESSAGES_PER_10_SECONDS)
		{
			GD.PrintErr($"[GameManager] Peer {peerId} exceeded message rate limit");
			return false;
		}
		
		if (timestamps.Count > 0 && currentTime - timestamps[timestamps.Count - 1] < MESSAGE_COOLDOWN_MS)
		{
			GD.PrintErr($"[GameManager] Peer {peerId} sending messages too quickly");
			return false;
		}
		
		timestamps.Add(currentTime);
		return true;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLobbyState(float timeLeft, bool paused, string videoUid)
	{
		if (_lobbyTimer != null && !_gameStarted)
		{
			_lobbyTimer.Stop();
			_lobbyTimer.WaitTime = timeLeft;
			if (!paused)
				_lobbyTimer.Start();
			else
				_lobbyTimer.Paused = true;
			
			CurrentVideoUid = videoUid;
		}
		
		if (timeLeft > 0)
			LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		EmitSignal(SignalName.LobbyStateSynced, timeLeft, paused, videoUid);
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void SyncPlayerTransform(int playerId, Vector2 position, float rotation)
	{
		if (playerId == Multiplayer.GetUniqueId())
			return;

		var world = GetWorld();
		if (world == null) return;
		var player = world.GetNodeOrNull<Node2D>(playerId.ToString());
		if (player == null) return;
		player.GlobalPosition = position;
		player.Rotation = rotation;
	}

	public void SendChatFromPlayer(int senderPeerId, string message, string mode = "IC")
	{
		var senderName = GetPlayerNameForMode(senderPeerId, mode);
		Rpc(MethodName.SendChatMessage, senderPeerId, senderName, message, mode);
	}

	private string GetRandomVideo()
	{
		var videos = new string[] {
			"uid://m44b5scm3sf2",
			"uid://baddbapvxhyjw",
			"uid://s331mwi01abw",
			"uid://bttyceok81cxh",
			"uid://cs4b47j652yok",
			"uid://c2kq5gljee3h0"
		};
		return videos[GD.RandRange(0, videos.Length - 1)];
	}

	private bool ValidateConnectionRate(int id)
	{
		long currentTime = (long)Time.GetTicksMsec();
		const long TIME_WINDOW_MS = 60000;
		
		if (_connectionAttempts.ContainsKey(id))
		{
			long lastAttempt = _connectionAttempts[id];
			if (currentTime - lastAttempt < TIME_WINDOW_MS)
			{
				return false;
			}
		}
		
		_connectionAttempts[id] = currentTime;
		return true;
	}

	public void SendLocalChatMessage(string message, string mode = "IC")
	{
		int peerId = Multiplayer.GetUniqueId();
		if (peerId == 0) peerId = 1;
		
		if (Multiplayer.IsServer())
		{
			if (!ValidateChatMessage(peerId, message)) return;
			SendChatFromPlayer(peerId, message, mode);
		}
		else
		{
			RpcId(1, MethodName.RequestSendChat, peerId, message, mode);
		}
	}
	private string GetPlayerNameForMode(int peerId, string mode)
	{
		if (mode == "OOC" || mode == "LOOC")
		{
			var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
			if (accountManager != null && accountManager.IsLoggedIn())
			{
				var discordTag = accountManager.GetDiscordTag();
				if (!string.IsNullOrEmpty(discordTag))
					return discordTag;
			}
		}
		
		var charData = GetPeerCharacterData(peerId);
		if (charData.ContainsKey("name"))
		{
			var playerName = (string)charData["name"];
			if (!string.IsNullOrEmpty(playerName))
				return playerName;
		}
		
		if (_playerNames.ContainsKey(peerId))
			return _playerNames[peerId];
			
		return $"Player {peerId}";
	}
	public string GetPlayerName(int peerId)
	{
		if (!IsGameRunning())
		{
			var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
			if (accountManager != null && accountManager.IsLoggedIn())
			{
				var discordTag = accountManager.GetDiscordTag();
				if (!string.IsNullOrEmpty(discordTag))
					return discordTag;
			}
		}
		
		var charData = GetPeerCharacterData(peerId);
		if (charData.ContainsKey("name"))
		{
			var playerName = (string)charData["name"];
			if (!string.IsNullOrEmpty(playerName))
				return playerName;
		}
		
		if (_playerNames.ContainsKey(peerId))
			return _playerNames[peerId];
			
		return $"Player {peerId}";
	}

	public void RefreshPlayerName()
	{
		int peerId = Multiplayer.GetUniqueId();
		if (peerId == 0) peerId = 1;
		
		var accountManager = GetNodeOrNull<AccountManager>("/root/AccountManager");
		if (accountManager != null && accountManager.IsLoggedIn())
		{
			var discordTag = accountManager.GetDiscordTag();
			if (!string.IsNullOrEmpty(discordTag))
			{
				_playerNames[peerId] = discordTag;
				GD.Print($"[GameManager] Refreshed player name to: {discordTag}");
			}
		}
	}

	private Node GetWorld()
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		if (world != null) return world;
		
		var communications = GetTree().Root.GetNodeOrNull<Control>("Communications");
		if (communications == null) return null;
		
		var subviewport = communications.GetNodeOrNull<SubViewportContainer>("HSplitContainer/SubViewportContainer");
		if (subviewport == null) return null;
		
		var viewport = subviewport.GetNodeOrNull<SubViewport>("SubViewport");
		if (viewport == null || viewport.GetChildCount() == 0) return null;
		
		return viewport.GetChild(0);
	}

	public void SpawnAllPlayers()
	{
		if (!Multiplayer.IsServer())
		{
			GD.PrintErr("[GameManager] SpawnAllPlayers can only be called on server");
			return;
		}
		
		GD.Print("[GameManager] Spawning all players...");
		var world = GetWorld();
		
		if (world == null)
		{
			GD.PrintErr("[GameManager] World not found! Cannot spawn players.");
			return;
		}
		
		var spawnPositions = new Vector2[] {
			new(2 * 32, 2 * 32),
			new(3 * 32, 3 * 32),
			new(1 * 32, 3 * 32),
			new(3 * 32, 1 * 32)
		};
		
		int spawnIndex = 0;
		foreach (int peerId in _connectedPeers)
		{
			var spawnPos = spawnPositions[spawnIndex % spawnPositions.Length];
			SpawnPlayer(peerId, spawnPos);
			spawnIndex++;
		}
	}

	private void SpawnPlayer(int peerId, Vector2 position)
	{
		var world = GetWorld();
		if (world == null || PlayerScene == null) return;
		
		var player = PlayerScene.Instantiate();
		player.Name = peerId.ToString();
		player.Set("Position", position);
		
		if (_peerCharacters.ContainsKey(peerId))
		{
			var charData = _peerCharacters[peerId];
			if (charData.ContainsKey("name"))
			{
				var playerName = (string)charData["name"];
				if (!string.IsNullOrEmpty(playerName))
					_playerNames[peerId] = playerName;
			}
		}
		
		world.AddChild(player, true);
	}

	public async void SpawnPlayer(int peerId, Vector2 spawnPos, Dictionary characterData = null)
	{
		if (!Multiplayer.IsServer())
		{
			GD.PrintErr("[GameManager] SpawnPlayer can only be called on server");
			return;
		}
		
		var world = GetWorld();
		if (world == null)
		{
			GD.PrintErr("[GameManager] World not found!");
			return;
		}
		
		var existingPlayer = world.GetNodeOrNull(peerId.ToString());
		if (existingPlayer != null)
		{
			GD.Print($"[GameManager] Player {peerId} already exists, skipping spawn");
			return;
		}
		
		if (PlayerScene == null)
		{
			GD.PrintErr("[GameManager] PlayerScene is null!");
			return;
		}
		
		var player = PlayerScene.Instantiate();
		if (player == null)
		{
			GD.PrintErr("[GameManager] Failed to instantiate player scene!");
			return;
		}
		
		string mobName = "DebugMob_" + GetUniqueMobId();
		if (characterData != null && characterData.ContainsKey("name"))
		{
			var name = (string)characterData["name"];
			if (!string.IsNullOrEmpty(name))
				mobName = name;
		}
		player.Name = mobName;
		player.Set("Position", spawnPos);
		
		if (characterData != null && characterData.Count > 0)
		{
			player.Set("CharacterData", characterData);
			
			if (characterData.ContainsKey("name"))
			{
				var playerName = (string)characterData["name"];
				if (!string.IsNullOrEmpty(playerName))
					player.Call("SetPlayerName", playerName);
			}
		}
		
		world.AddChild(player, true);
		await ToSignal(GetTree(), "process_frame");
		
		if (player.HasMethod("Initialize"))
			player.Call("Initialize");
	}
	
	private Dictionary GenerateRandomCharacterData()
	{
		var characterData = new Dictionary
		{
			["name"] = GenerateRandomName(),
			["age"] = GD.RandRange(18, 50),
			["religion"] = GenerateRandomReligion(),
			["clothing"] = "Standard Uniform",
			["underwear"] = "1",
			["hair_style"] = GenerateRandomHairStyle(),
			["facial_hair_style"] = GenerateRandomFacialHairStyle(),
			["underwear_style"] = "1",
			["undershirt_style"] = GenerateRandomUndershirtStyle(),
			["hair_base_color"] = GenerateRandomColor(),
			["hair_gradient_color"] = GenerateRandomColor(),
			["eye_color"] = GenerateRandomColor(),
			["race"] = GenerateRandomRace(),
			["gender"] = GenerateRandomGender(),
			["traits"] = new Godot.Collections.Array<string>(),
			["role_priorities"] = new Dictionary(),
			["background"] = GenerateRandomBackground(),
			["randomize_name"] = false,
			["randomize_appearance"] = false,
			["origin"] = GenerateRandomOrigin(),
			["relations"] = "",
			["pref_squad"] = "",
			["assigned_roles"] = new Dictionary(),
			["is_debug_mob"] = true
		};
		
		return characterData;
	}
	
	private string GenerateRandomName()
	{
		var firstNames = new string[] { "John", "Jane", "Alex", "Chris", "Sam", "Taylor", "Jordan", "Morgan", "Casey", "Riley", "Jamie", "Avery", "Cameron", "Dakota", "Emery", "Finley", "Harper", "Quinn", "Reese", "Sage" };
		var lastNames = new string[] { "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Wilson", "Anderson", "Taylor", "Thomas", "Hernandez", "Moore", "Martin", "Jackson", "Thompson", "White" };
		
		return $"{firstNames[GD.RandRange(0, firstNames.Length - 1)]} {lastNames[GD.RandRange(0, lastNames.Length - 1)]}";
	}
	
	private string GenerateRandomReligion()
	{
		var religions = new string[] { "Atheist", "Christian", "Muslim", "Hindu", "Buddhist", "Jewish", "Agnostic", "Scientologist", "Pagan", "Spiritual" };
		return religions[GD.RandRange(0, religions.Length - 1)];
	}
	
	private string GenerateRandomHairStyle()
	{
		var styles = new string[] { "(1)", "(2)", "(3)", "(4)", "(5)", "(6)", "(7)", "(8)", "(9)", "(10)", "(11)", "(12)", "(13)", "(14)", "(15)" };
		return styles[GD.RandRange(0, styles.Length - 1)];
	}
	
	private string GenerateRandomFacialHairStyle()
	{
		var styles = new string[] { "_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8", "_9", "_10" };
		return styles[GD.RandRange(0, styles.Length - 1)];
	}
	
	private string GenerateRandomUndershirtStyle()
	{
		var styles = new string[] { "1", "2", "3", "4", "5" };
		return styles[GD.RandRange(0, styles.Length - 1)];
	}
	
	private string GenerateRandomColor()
	{
		var r = GD.RandRange(0, 255);
		var g = GD.RandRange(0, 255);
		var b = GD.RandRange(0, 255);
		return $"#{r:X2}{g:X2}{b:X2}";
	}
	
	private string GenerateRandomRace()
	{
		var races = new string[] { "Western", "Eastern", "African", "Asian", "Hispanic", "Mixed" };
		return races[GD.RandRange(0, races.Length - 1)];
	}
	
	private string GenerateRandomGender()
	{
		var genders = new string[] { "Male", "Female", "Non-Binary" };
		return genders[GD.RandRange(0, genders.Length - 1)];
	}
	
	private string GenerateRandomBackground()
	{
		var backgrounds = new string[] 
		{ 
			"Former civilian contractor", 
			"Ex-military personnel", 
			"Scientific researcher", 
			"Corporate employee",
			"Colonial settler",
			"Space explorer",
			"Medical professional",
			"Engineer by trade",
			"Security officer",
			"Logistics specialist"
		};
		return backgrounds[GD.RandRange(0, backgrounds.Length - 1)];
	}
	
	private string GenerateRandomOrigin()
	{
		var origins = new string[] 
		{ 
			"Earth", 
			"Mars Colony", 
			"Luna Base", 
			"Titan Station",
			"Europa Outpost",
			"Venus Orbital",
			"Deep Space Born",
			"Jupiter Station",
			"Saturn Ring",
			"Mercury Mining"
		};
		return origins[GD.RandRange(0, origins.Length - 1)];
	}

	private int _mobIdCounter = 1000;
	public int GetUniqueMobId()
	{
		return _mobIdCounter++;
	}

	public void UpdatePlayerCount()
	{
		if (_isHosting || _isConnected)
		{
			PlayerCount = Multiplayer.GetPeers().Length + 1;
			EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
			GD.Print($"[GameManager] Player count: {PlayerCount}/{MaxPlayers}");
		}
	}

	public void SyncMedia(string type, string path, int loops = 0, float volume = 0.5f)
	{
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.BroadcastMediaSync, type, path, loops, volume);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastMediaSync(string type, string path, int loops, float volume)
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

	public override void _ExitTree()
	{
		LeaveGame();
	}
}