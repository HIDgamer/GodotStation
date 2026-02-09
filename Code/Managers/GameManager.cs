using Godot;
using Godot.Collections;
using System.Linq;

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
	
	private GameState _currentGameState = GameState.Menu;

	private ENetMultiplayerPeer _peer = new();
	private Timer _lobbyTimer;
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

	private const string CharactersDir = "user://characters/";
	private string _charactersDirOverride = null;

	public bool IsHost => _isHosting;
	public GameState CurrentGameState => _currentGameState;

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
		
		// Discord RPC integration
		var discord = GetNode<DiscordRPC>("/root/DiscordRPC");
		
		// Connect to game state signals
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
		
		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateServer(port, MaxPlayers);
		
		if (error == Error.Ok)
		{
			_peer.RefuseNewConnections = false;
			Multiplayer.MultiplayerPeer = _peer;
			PlayerCount = 1;
			_connectedPeers.Add(1);
			_isHosting = true;
			
			var prefManager = GetNode("/root/PreferenceManager");
			var playerData = (Dictionary)prefManager.Call("get_character_data");
			var hostName = playerData.ContainsKey("name") ? (string)playerData["name"] : "Host";
			if (string.IsNullOrEmpty(hostName)) hostName = "Host";
			_playerNames[1] = hostName;
			
			if (!playerData.ContainsKey("peer_id"))
				playerData["peer_id"] = 1;
			_peerCharacters[1] = playerData;
			prefManager.Call("set_peer_character_data", 1, playerData);
			GD.Print($"[GameManager] Host character data stored - Name: {hostName}, Race: {(playerData.ContainsKey("race") ? (string)playerData["race"] : "none")}");
			
			SetupLobbyTimer();
			RegisterWithLobby(port);
			EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
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
		
		_lobbyManager.RegisterServer(serverInfo);
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

	public void JoinGame(string address, int port = -1)
	{
		if (port == -1) port = DefaultPort;
		
		_peer = new ENetMultiplayerPeer();
		var error = _peer.CreateClient(address, port);
		
		if (error == Error.Ok)
		{
			Multiplayer.MultiplayerPeer = _peer;
			var timeoutTimer = new Timer { WaitTime = 5.0f, OneShot = true };
			timeoutTimer.Timeout += OnJoinTimeout;
			AddChild(timeoutTimer);
			timeoutTimer.Start();
		}
		else
		{
			GD.PrintErr($"Failed to create client: {error}");
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	public void LeaveGame()
	{
		if (Multiplayer.MultiplayerPeer != null)
		{
			Multiplayer.MultiplayerPeer.Close();
			Multiplayer.MultiplayerPeer = null;
		}
		
		if (_lobbyManager != null && _isHosting)
		{
			_lobbyManager.UnregisterServer();
		}
		
		_isHosting = false;
		_isConnected = false;
		PlayerCount = 0;
		
		GD.Print("[GameManager] Left game");
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
	}

	private void OnJoinTimeout()
	{
		if (!Multiplayer.HasMultiplayerPeer() || Multiplayer.GetUniqueId() == 0)
		{
			GD.PrintErr("Failed to connect: No server found");
			_peer.Close();
			Multiplayer.MultiplayerPeer = null;
			EmitSignal(SignalName.ConnectionFailed);
		}
	}

	private void SetupLobbyTimer()
	{
		CurrentVideoUid = GetRandomVideo();
		LobbyTimeLeft = 300.0f;
		
		_lobbyTimer = new Timer { WaitTime = LobbyTimeLeft, OneShot = true };
		_lobbyTimer.Timeout += OnLobbyTimeout;
		AddChild(_lobbyTimer);
		_lobbyTimer.Start();

		var updateTimer = new Timer { WaitTime = 1.0f, Autostart = true };
		updateTimer.Timeout += UpdateLobbyTime;
		AddChild(updateTimer);

		if (Multiplayer.IsServer() && !string.IsNullOrEmpty(CurrentVideoUid))
			EmitSignal(SignalName.MediaSyncReceived, "video", CurrentVideoUid, 0, 0.5f);
	}

	private void UpdateLobbyTime()
	{
		if (_lobbyTimer != null && !_lobbyTimer.IsStopped())
		{
			LobbyTimeLeft = (float)_lobbyTimer.TimeLeft;
			if (Multiplayer.IsServer())
				Rpc(MethodName.SyncLobbyStateToAll, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		}
	}

	private void OnLobbyTimeout()
	{
		if (Multiplayer.IsServer())
		{
			EmitSignal(SignalName.LobbyTimeout);
			Rpc(MethodName.SyncLobbyStateToAll, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
		}
	}

	private Node GetWorld()
	{
		var worlds = GetTree().GetNodesInGroup("World");
		return worlds.Count > 0 ? worlds[0] : null;
	}

	public async void StartGame()
	{
		if (Multiplayer.IsServer())
		{
			GD.Print($"[GameManager] StartGame called on server");
			_gameStarted = true;
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
				foreach (var peerId in _connectedPeers)
				{
					if (peerId > 0)
					{
						var spawnPos = spawnPositions[spawnIndex % spawnPositions.Length];
						SpawnPlayer(peerId, spawnPos);
						spawnIndex++;
					}
				}
			}
			
			Rpc(MethodName.ClientStartGame);
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
					player.Call("SetPlayerName", playerName);
			}
		}
		
		world.AddChild(player, true);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
	private void ClientStartGame()
	{
		_gameStarted = true;
		EmitSignal(SignalName.GameStarted);
	}

	private void OnPeerConnected(long id)
	{
		var peerId = (int)id;
		
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
			Rpc(MethodName.SyncLobbyStateToAll, LobbyTimeLeft, LobbyTimerPaused, CurrentVideoUid);
			RpcId(peerId, MethodName.SyncIngameTime, IngameTime);
			
			foreach (var kvp in _peerCharacters)
			{
				if (kvp.Key != peerId)
					RpcId(peerId, MethodName.SyncPlayerAppearance, kvp.Key, kvp.Value);
			}
			UpdatePlayerCount();
		}
	}

	private void OnPeerDisconnected(long id)
	{
		var peerId = (int)id;
		_connectedPeers.Remove(peerId);
		_playerNames.Remove(peerId);
		_peerCharacters.Remove(peerId);
		_messageTimestamps.Remove(peerId);
		_connectionAttempts.Remove(peerId);
		
		PlayerCount = _connectedPeers.Count;
		
		GD.Print($"[GameManager] Peer {id} disconnected. Remaining players: {PlayerCount}");
		EmitSignal(SignalName.PlayerLeft, peerId);
		EmitSignal(SignalName.PlayersUpdated);
		EmitSignal(SignalName.PlayerCountChanged, PlayerCount);
		
		if (Multiplayer.IsServer())
		{
			var world = GetWorld();
			if (world != null)
			{
				var playerNode = world.GetNodeOrNull(peerId.ToString());
				playerNode?.QueueFree();
			}
			UpdatePlayerCount();
		}
	}

	private void OnConnectedToServer()
	{
		GD.Print("[GameManager] Successfully connected to server");
		_isConnected = true;
		UpdatePlayerCount();
		
		var prefManager = GetNode("/root/PreferenceManager");
		var playerData = (Dictionary)prefManager.Call("get_character_data");
		var myId = Multiplayer.GetUniqueId();
		playerData["peer_id"] = myId;
		
		var playerName = playerData.ContainsKey("name") ? (string)playerData["name"] : $"Player {myId}";
		if (string.IsNullOrEmpty(playerName))
			playerName = $"Player {myId}";
		_playerNames[myId] = playerName;
		
		_peerCharacters[myId] = playerData;
		prefManager.Call("set_peer_character_data", myId, playerData);
		
		RpcId(1, MethodName.ReceivePlayerAppearance, myId, playerData);
		GD.Print($"[GameManager] Sent character data to server - Name: {playerName}, Race: {(playerData.ContainsKey("race") ? (string)playerData["race"] : "none")}");
	}

	private void OnConnectionFailed()
	{
		GD.PrintErr("[GameManager] Connection to server failed");
		Multiplayer.MultiplayerPeer = null;
		EmitSignal(SignalName.ConnectionFailed);
	}

	private void OnServerDisconnected()
	{
		GD.Print("[GameManager] Disconnected from server");
		LeaveGame();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ReceivePlayerAppearance(int peerId, Dictionary playerData)
	{
		if (!Multiplayer.IsServer()) return;
		if (!ValidateRpcSender(peerId)) return;
		
		_peerCharacters[peerId] = playerData;
		
		if (playerData.ContainsKey("name"))
		{
			var playerName = (string)playerData["name"];
			if (!string.IsNullOrEmpty(playerName))
				_playerNames[peerId] = playerName;
		}
		
		var prefManager = GetNode("/root/PreferenceManager");
		prefManager.Call("set_peer_character_data", peerId, playerData);
		
		Rpc(MethodName.SyncPlayerAppearance, peerId, playerData);
		
		if (_gameStarted)
		{
			var world = GetWorld();
			if (world != null)
			{
				var existingPlayer = world.GetNodeOrNull(peerId.ToString());
				if (existingPlayer != null)
				{
					var spriteSystem = existingPlayer.GetNodeOrNull("SpriteSystem");
					spriteSystem?.Call("ReloadAppearance");
					
					if (playerData.ContainsKey("name"))
					{
						var playerName = (string)playerData["name"];
						if (!string.IsNullOrEmpty(playerName))
							existingPlayer.Call("SetPlayerName", playerName);
					}
				}
			}
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPlayerAppearance(int peerId, Dictionary playerData)
	{
		var prefManager = GetNode("/root/PreferenceManager");
		prefManager.Call("set_peer_character_data", peerId, playerData);
		
		if (playerData.ContainsKey("name"))
		{
			var playerName = (string)playerData["name"];
			if (!string.IsNullOrEmpty(playerName))
				_playerNames[peerId] = playerName;
		}
		
		CallDeferred(MethodName.ApplyAppearanceDeferred, peerId, playerData);
	}

	private void ApplyAppearanceDeferred(int peerId, Dictionary playerData)
	{
		var world = GetWorld();
		if (world != null)
		{
			var player = world.GetNodeOrNull(peerId.ToString());
			if (player != null)
			{
				var spriteSystem = player.GetNodeOrNull("SpriteSystem");
				if (spriteSystem != null)
					spriteSystem.Call("ReloadAppearance");
					
				if (playerData.ContainsKey("name"))
				{
					var playerName = (string)playerData["name"];
					if (!string.IsNullOrEmpty(playerName))
						player.Call("SetPlayerName", playerName);
				}
			}
			else
			{
				GetTree().CreateTimer(0.1).Timeout += () => ApplyAppearanceDeferred(peerId, playerData);
			}
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIngameTime(float time)
	{
		IngameTime = time;
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SendChatMessage(int senderPeerId, string senderName, string message, string mode = "IC")
	{
		if (Multiplayer.IsServer())
		{
			if (!ValidateRpcSender(senderPeerId) || !ValidateMessageRate(senderPeerId))
				return;
			
			message = message.Trim();
			if (string.IsNullOrEmpty(message) || message.Length > MAX_MESSAGE_LENGTH)
				return;
			
			var actualName = _playerNames.ContainsKey(senderPeerId) ? _playerNames[senderPeerId] : $"Player {senderPeerId}";
			Rpc(MethodName.BroadcastChatMessage, senderPeerId, actualName, message, mode);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastChatMessage(int senderPeerId, string senderName, string message, string mode)
	{
		EmitSignal(SignalName.ChatMessageReceived, senderPeerId, senderName, message, mode);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncLobbyStateToAll(float timeLeft, bool paused, string videoUid)
	{
		LobbyTimeLeft = timeLeft;
		LobbyTimerPaused = paused;
		CurrentVideoUid = videoUid;
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void BroadcastMediaSync(string type, string path, int loops, float volume)
	{
		EmitSignal(SignalName.MediaSyncReceived, type, path, loops, volume);
	}

	public void SyncMedia(string type, string path, int loops = 0, float volume = 0.5f)
	{
		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.BroadcastMediaSync, type, path, loops, volume);
		}
	}

	public void SendChatFromPlayer(int senderPeerId, string message, string mode = "IC")
	{
		var senderName = _playerNames.ContainsKey(senderPeerId) ? _playerNames[senderPeerId] : $"Player {senderPeerId}";
		Rpc(MethodName.SendChatMessage, senderPeerId, senderName, message, mode);
	}

	private string GetRandomVideo()
	{
		var videos = new string[] {
			"uid://chnqslhqxbscu",
			"uid://c5p0bxp7i8rcp"
		};
		return videos[GD.RandRange(0, videos.Length - 1)];
	}

	private bool ValidateConnectionRate(int id)
	{
		var currentTime = (long)Time.GetTicksMsec();
		if (_connectionAttempts.TryGetValue(id, out var lastAttempt))
		{
			if (currentTime - lastAttempt < 1000)
				return false;
		}
		_connectionAttempts[id] = currentTime;
		return true;
	}

	private bool ValidateRpcSender(int senderId)
	{
		var remote = Multiplayer.GetRemoteSenderId();
		if (remote == 0 && senderId == Multiplayer.GetUniqueId())
			return true;
		return remote == senderId;
	}

	private bool ValidateMessageRate(int peerId)
	{
		var currentTime = (long)Time.GetTicksMsec();
		if (!_messageTimestamps.ContainsKey(peerId))
			_messageTimestamps[peerId] = new System.Collections.Generic.List<long>();
		
		var timestamps = _messageTimestamps[peerId];
		
		if (timestamps.Count > 0 && currentTime - timestamps[timestamps.Count - 1] < MESSAGE_COOLDOWN_MS)
			return false;
		
		timestamps.RemoveAll(t => currentTime - t >= 10000);
		
		if (timestamps.Count >= MAX_MESSAGES_PER_10_SECONDS)
			return false;
		
		timestamps.Add(currentTime);
		return true;
	}

	public Dictionary GetPeerCharacterData(int peerId)
	{
		return _peerCharacters.ContainsKey(peerId) ? _peerCharacters[peerId] : new Dictionary();
	}

	public void SetPeerCharacterData(int peerId, Dictionary data)
	{
		_peerCharacters[peerId] = data;
	}

	public Godot.Collections.Array GetSlotNames()
	{
		var names = new Godot.Collections.Array();
		for (int i = 0; i < SLOT_COUNT; i++)
		{
			var data = LoadSlot(i);
			if (data.Count > 0 && data.ContainsKey("name"))
				names.Add((string)data["name"]);
			else
				names.Add($"Slot {i + 1}");
		}
		return names;
	}

	public Dictionary LoadSlot(int slot)
	{
		var dir = _charactersDirOverride ?? CharactersDir;
		var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
		foreach (var letter in letters)
		{
			var charData = LoadCharacter(letter.ToString(), slot);
			if (charData.Count > 0)
				return charData;
		}
		
		var otherData = LoadCharacter("Other", slot);
		if (otherData.Count > 0)
			return otherData;
		
		return new Dictionary();
	}

	public void SaveSlot(int slot, Dictionary characterData)
	{
		var name = characterData.ContainsKey("name") ? (string)characterData["name"] : "Unnamed";
		if (string.IsNullOrEmpty(name))
			name = "Unnamed";
		var firstLetter = name.Substring(0, 1).ToUpper();
		if (firstLetter.Length == 0 || !char.IsLetter(firstLetter[0]))
			firstLetter = "Other";
		SaveCharacter(firstLetter, slot, characterData);
	}

	private Dictionary LoadCharacter(string letter, int slot)
	{
		var folderPath = (_charactersDirOverride ?? CharactersDir) + letter + "/";
		if (!DirAccess.DirExistsAbsolute(folderPath))
			return new Dictionary();
		
		using var dir = DirAccess.Open(folderPath);
		if (dir == null)
			return new Dictionary();
		
		dir.ListDirBegin();
		var fileName = dir.GetNext();
		while (!string.IsNullOrEmpty(fileName))
		{
			if (fileName.EndsWith($"_slot{slot}.json"))
			{
				var filePath = folderPath + fileName;
				using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read);
				if (file != null)
				{
					var jsonString = file.GetAsText();
					var json = new Json();
					if (json.Parse(jsonString) == Error.Ok)
					{
						dir.ListDirEnd();
						var data = json.Data.AsGodotDictionary();
						if (!data.ContainsKey("name"))
							data["name"] = fileName.Replace($"_slot{slot}.json", "");
						return data;
					}
				}
			}
			fileName = dir.GetNext();
		}
		dir.ListDirEnd();
		return new Dictionary();
	}

	private void SaveCharacter(string letter, int slot, Dictionary characterData)
	{
		letter = letter.Substring(0, 1).ToUpper();
		if (letter.Length == 0 || !char.IsLetter(letter[0]))
			letter = "Other";
		
		var folderPath = (_charactersDirOverride ?? CharactersDir) + letter + "/";
		if (!DirAccess.DirExistsAbsolute(folderPath))
		{
			var error = DirAccess.MakeDirRecursiveAbsolute(folderPath);
			if (error != Error.Ok)
				return;
		}
		
		characterData["_slot"] = slot;
		characterData["_saved_at"] = Time.GetDatetimeStringFromSystem();
		
		var safeName = characterData.ContainsKey("name") ? ((string)characterData["name"]).Replace("/", "_").Replace("\\", "_") : "Unnamed";
		var filePath = folderPath + safeName + $"_slot{slot}.json";
		var jsonString = Json.Stringify(characterData, "\t");
		using var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Write);
		if (file != null)
			file.StoreString(jsonString);
	}

	public const int SLOT_COUNT = 10;
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	public async void RequestSpawnItem(string itemScenePath, Vector2 position, int quantity = 1)
	{
		if (!Multiplayer.IsServer()) return;
		
		var scene = GD.Load<PackedScene>(itemScenePath);
		if (scene == null) return;
		
		var worlds = GetTree().GetNodesInGroup("World");
		if (worlds.Count == 0) return;
		
		var world = worlds[0];
		var item = scene.Instantiate<WorldItem>();
		item.Quantity = quantity;
		item.PrepareSpawn(position);
		world.AddChild(item, true);
		await ToSignal(GetTree(), "process_frame");
		item.InitAtPosition(position);
	}

	public override void _ExitTree()
	{
		LeaveGame();
	}
}