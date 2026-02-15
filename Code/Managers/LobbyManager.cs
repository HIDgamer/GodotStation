using Godot;
using Godot.Collections;
using System;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;
using ClientWebSocket = System.Net.WebSockets.ClientWebSocket;
using WebSocketState = System.Net.WebSockets.WebSocketState;
using WebSocketMessageType = System.Net.WebSockets.WebSocketMessageType;
using Array = Godot.Collections.Array;

public partial class LobbyManager : Node
{
	[Export] public string ApiUrl = "https://godotstation.duckdns.org";
	[Export] public float HeartbeatInterval = 10.0f;
	private const int MinPort = 1024;
	private const int MaxPort = 65535;
	
	[Signal] public delegate void ServerListUpdatedEventHandler(Array servers);
	[Signal] public delegate void ServerRegisteredEventHandler(string serverId);
	[Signal] public delegate void ServerRegistrationFailedEventHandler(string error);
	
	private HttpClient _httpClient;
	private ClientWebSocket _webSocket;
	private AccountManager _accountManager;
	private Godot.Timer _heartbeatTimer;
	private string _currentServerId = "";
	private bool _isHosting = false;
	private CancellationTokenSource _wsCancellation;
	private FriendsManager _friendsManager;
	private ChatManager _chatManager;
	private Dictionary _lastServerRegistration;
	private Dictionary _pendingServerRegistration;
	private bool _registrationInFlight = false;
	private long _lastReregisterAttemptMs = 0;
	private const long ReregisterCooldownMs = 15000;
	
	public override void _Ready()
	{
		ProcessMode = ProcessModeEnum.Always;
		
		_httpClient = new HttpClient();
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		_friendsManager = GetNodeOrNull<FriendsManager>("/root/FriendsManager");
		_chatManager = GetNodeOrNull<ChatManager>("/root/ChatManager");
		
		// Setup heartbeat timer
		_heartbeatTimer = new Godot.Timer();
		_heartbeatTimer.WaitTime = HeartbeatInterval;
		_heartbeatTimer.ProcessMode = ProcessModeEnum.Always;
		_heartbeatTimer.Timeout += SendHeartbeat;
		AddChild(_heartbeatTimer);
		
		// Connect to WebSocket for real-time updates
		CallDeferred(MethodName.ConnectWebSocket);
	}
	
	// Connect to WebSocket for real-time server list updates
	private async void ConnectWebSocket()
	{
		if (!_accountManager.IsLoggedIn())
		{
			// Retry after login
			await Task.Delay(2000);
			CallDeferred(MethodName.ConnectWebSocket);
			return;
		}

		if (_webSocket != null && _webSocket.State == WebSocketState.Open)
			return;
		
		try
		{
			_wsCancellation?.Cancel();
			_wsCancellation = new CancellationTokenSource();
			_webSocket?.Dispose();
			_webSocket = new ClientWebSocket();
			
			var wsUrl = ApiUrl.Replace("http://", "ws://").Replace("https://", "wss://");
			await _webSocket.ConnectAsync(new System.Uri(wsUrl), _wsCancellation.Token);
			
			// Authenticate WebSocket
			var authMsg = new Dictionary
			{
				{ "type", "auth" },
				{ "token", _accountManager.GetAuthToken() }
			};
			var authJson = Json.Stringify(authMsg);
			await _webSocket.SendAsync(
				new ArraySegment<byte>(Encoding.UTF8.GetBytes(authJson)),
				WebSocketMessageType.Text,
				true,
				_wsCancellation.Token
			);
			
			GD.Print("[LobbyManager] WebSocket connected");
			
			// Start listening for messages
			_ = Task.Run(ListenWebSocket);
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] WebSocket connection failed: {e.Message}");
			CallDeferred(MethodName.ScheduleWebSocketReconnect);
		}
	}

	private async void ScheduleWebSocketReconnect()
	{
		await Task.Delay(2000);
		if (IsInsideTree())
		{
			ConnectWebSocket();
		}
	}
	
	// Listen for WebSocket messages
	private async Task ListenWebSocket()
	{
		var buffer = new byte[4096];
		
		while (_webSocket?.State == WebSocketState.Open && !_wsCancellation.Token.IsCancellationRequested)
		{
			try
			{
				var result = await _webSocket.ReceiveAsync(
					new ArraySegment<byte>(buffer),
					_wsCancellation.Token
				);
				
				if (result.MessageType == WebSocketMessageType.Close)
				{
					break;
				}

				if (result.MessageType == WebSocketMessageType.Text)
				{
					var builder = new StringBuilder();
					builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
					while (!result.EndOfMessage)
					{
						result = await _webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), _wsCancellation.Token);
						if (result.MessageType != WebSocketMessageType.Text)
							break;
						builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
					}
					var message = builder.ToString();
					CallDeferred(MethodName.HandleWebSocketMessage, message);
				}
			}
			catch (System.Exception e)
			{
				GD.PrintErr($"[LobbyManager] WebSocket error: {e.Message}");
				break;
			}
		}

		if (_wsCancellation != null && !_wsCancellation.IsCancellationRequested)
		{
			CallDeferred(MethodName.ScheduleWebSocketReconnect);
		}
	}
	
	// Handle WebSocket messages
	private void HandleWebSocketMessage(string message)
	{
		try
		{
			var jsonParser = new Json();
			if (jsonParser.Parse(message) != Error.Ok) return;
			
			var data = jsonParser.Data.AsGodotDictionary();
			
			if (!data.ContainsKey("type")) return;
			
			var type = data["type"].ToString();
			
			switch (type)
			{
				case "server_list_update":
					if (data.ContainsKey("servers"))
					{
						var servers = data["servers"].AsGodotArray();
						EmitSignal(SignalName.ServerListUpdated, servers);
					}
					break;
				
				case "auth_success":
					GD.Print("[LobbyManager] WebSocket authenticated");
					break;

				case "friend_request":
					_friendsManager?.RefreshPendingRequests();
					break;

				case "friend_accepted":
					_friendsManager?.RefreshFriendsList();
					break;

				case "friend_status":
					if (data.ContainsKey("user_id") && data.ContainsKey("online"))
					{
						var userId = VariantToInt(data["user_id"]);
						var online = data["online"].AsBool();
						_friendsManager?.OnFriendStatusUpdate(userId, online);
					}
					break;

				case "chat_message":
					_chatManager?.OnMessageReceived(data);
					break;
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Error handling WebSocket message: {e.Message}");
		}
	}
	
	// Register server in lobby
	public async void RegisterDedicatedServer(string serverName, int port, string map)
	{
		GD.Print("[LobbyManager] Registering as Dedicated Server...");

		var data = new Dictionary
		{
			{ "name", serverName },
			{ "map", map },
			{ "port", port },
			{ "is_dedicated", true },
			{ "max_players", 32 },
			{ "current_players", 0 },
			{ "ip_address", "129.213.29.53" },
			{ "description", "Official Dedicated Server" }
		};
		string serverApiKey = OS.GetEnvironment("SERVER_API_KEY");
		_httpClient.DefaultRequestHeaders.Clear();
		_httpClient.DefaultRequestHeaders.Add("X-Server-Key", serverApiKey);

		var json = Json.Stringify(data);
		var content = new StringContent(json, Encoding.UTF8, "application/json");
		
		var response = await _httpClient.PostAsync($"{ApiUrl}/api/servers/register-dedicated", content);
		if (response.IsSuccessStatusCode)
		{
			var responseText = await response.Content.ReadAsStringAsync();
			var result = Json.ParseString(responseText).AsGodotDictionary();
			_currentServerId = result["server_id"].ToString();
			_isHosting = true;
			_heartbeatTimer.Start();
			GD.Print($"[LobbyManager] Dedicated Server Registered: {_currentServerId}");
		}
	}
	public void RegisterServer(Dictionary serverInfo)
	{
		RegisterServerInternal(serverInfo, false);
	}

	private async void RegisterServerInternal(Dictionary serverInfo, bool force)
	{
		if (!_accountManager.IsLoggedIn())
		{
			EmitSignal(SignalName.ServerRegistrationFailed, "Not logged in");
			return;
		}

		if (_registrationInFlight)
		{
			if (force)
				return;
			_pendingServerRegistration = CloneDictionary(serverInfo);
			return;
		}

		_registrationInFlight = true;
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
			
			string serverName = "GodotStation Server";
			string map = "Station";
			string gamemode = "Sandbox";
			int maxPlayers = 8;
			int currentPlayers = 1;
			int port = 7777;
			if (serverInfo.ContainsKey("port")) 
				port = (int)serverInfo["port"];
			else if (gameManager != null)
				port = gameManager.DefaultPort;
			string ipAddress = GetPublicIP();
			bool passwordProtected = false;
			string description = "";
			
			if (serverInfo.ContainsKey("name") && !string.IsNullOrEmpty(serverInfo["name"].ToString()))
				serverName = serverInfo["name"].ToString();
			if (serverInfo.ContainsKey("map") && !string.IsNullOrEmpty(serverInfo["map"].ToString()))
				map = serverInfo["map"].ToString();
			if (serverInfo.ContainsKey("gamemode") && !string.IsNullOrEmpty(serverInfo["gamemode"].ToString()))
				gamemode = serverInfo["gamemode"].ToString();
			if (serverInfo.ContainsKey("max_players")) 
				maxPlayers = (int)serverInfo["max_players"];
			if (serverInfo.ContainsKey("current_players")) 
				currentPlayers = (int)serverInfo["current_players"];
			if (serverInfo.ContainsKey("port")) 
				port = (int)serverInfo["port"];
			if (serverInfo.ContainsKey("ip_address") && !string.IsNullOrEmpty(serverInfo["ip_address"].ToString()))
				ipAddress = serverInfo["ip_address"].ToString();
			if (serverInfo.ContainsKey("password_protected")) 
				passwordProtected = (bool)serverInfo["password_protected"];
			if (serverInfo.ContainsKey("description")) 
				description = serverInfo["description"].ToString();
			if (string.IsNullOrWhiteSpace(serverName))
				serverName = "GodotStation Server";
			if (string.IsNullOrWhiteSpace(map))
				map = "Station";
			if (string.IsNullOrWhiteSpace(gamemode))
				gamemode = "Sandbox";
			serverName = serverName.Trim();
			map = map.Trim();
			gamemode = gamemode.Trim();
			description ??= "";

			if (port < MinPort || port > MaxPort)
			{
				EmitSignal(SignalName.ServerRegistrationFailed, $"Invalid port {port}. Expected {MinPort}-{MaxPort}.");
				return;
			}
			if (ipAddress == "127.0.0.1" || ipAddress == "0.0.0.0")
			{
				EmitSignal(SignalName.ServerRegistrationFailed, "Could not resolve a public IP. Ensure internet access and port forwarding are configured.");
				return;
			}
			
			if (gameManager != null)
			{
				try
				{
					var gmMap = gameManager.CurrentMap;
					var gmGamemode = gameManager.Gamemode;
					
					if (!serverInfo.ContainsKey("map") && !string.IsNullOrEmpty(gmMap))
						map = gmMap;
					if (!serverInfo.ContainsKey("gamemode") && !string.IsNullOrEmpty(gmGamemode))
						gamemode = gmGamemode;
					if (!serverInfo.ContainsKey("max_players"))
						maxPlayers = gameManager.MaxPlayers;
					if (!serverInfo.ContainsKey("current_players"))
						currentPlayers = gameManager.PlayerCount;
					if (!serverInfo.ContainsKey("port"))
						port = gameManager.DefaultPort;
				}
				catch (Exception e)
				{
					GD.PrintErr($"[LobbyManager] Warning: Could not read GameManager properties: {e.Message}");
				}
			}
			
			var data = new Dictionary
			{
				{ "name", serverName },
				{ "map", map },
				{ "gamemode", gamemode },
				{ "max_players", maxPlayers },
				{ "current_players", currentPlayers },
				{ "port", port },
				{ "ip_address", ipAddress },
				{ "password_protected", passwordProtected },
				{ "description", description }
			};
			_lastServerRegistration = data;
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			GD.Print($"[LobbyManager] Registering server: {serverName} at {ipAddress}:{port} | Map: {map} | Mode: {gamemode}");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/servers/register", content);
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("server_id"))
					{
						_currentServerId = result["server_id"].ToString();
						_isHosting = true;
						_heartbeatTimer.Start();
						
						EmitSignal(SignalName.ServerRegistered, _currentServerId);
						GD.Print($"[LobbyManager] Server registered: {_currentServerId}");
					}
				}
			}
			else
			{
				var error = ParseError(responseText);
				EmitSignal(SignalName.ServerRegistrationFailed, error);
				GD.PrintErr($"[LobbyManager] Server registration failed: {error}");
				GD.PrintErr($"[LobbyManager] Response: {responseText}");
			}
		}
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.ServerRegistrationFailed, errorMsg);
			GD.PrintErr($"[LobbyManager] {errorMsg}");
		}
		finally
		{
			_registrationInFlight = false;

			if (!force && _pendingServerRegistration != null)
			{
				var pending = _pendingServerRegistration;
				_pendingServerRegistration = null;
				if (!_isHosting)
					RegisterServerInternal(pending, false);
			}
		}
	}
	
	// Send heartbeat to keep server alive in lobby
	private async void SendHeartbeat()
	{
		if (!_isHosting || string.IsNullOrEmpty(_currentServerId))
			return;
		
		try
		{
			var gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
			int playerCount = 1;
			
			if (gameManager != null)
			{
				try
				{
					playerCount = gameManager.PlayerCount;
				}
				catch
				{
					// Use default
				}
			}
			
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary
			{
				{ "server_id", _currentServerId },
				{ "current_players", playerCount }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/servers/heartbeat", content);
			if (!response.IsSuccessStatusCode)
			{
				GD.PrintErr($"[LobbyManager] Heartbeat failed with status {(int)response.StatusCode}");
				AttemptServerReregister(response.StatusCode);
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Heartbeat failed: {e.Message}");
		}
	}

	private void AttemptServerReregister(HttpStatusCode statusCode)
	{
		if (_lastServerRegistration == null || _lastServerRegistration.Count == 0)
			return;

		if (statusCode != HttpStatusCode.NotFound && statusCode != HttpStatusCode.Forbidden && statusCode != HttpStatusCode.Unauthorized)
			return;

		var now = (long)Time.GetTicksMsec();
		if (now - _lastReregisterAttemptMs < ReregisterCooldownMs)
			return;

		_lastReregisterAttemptMs = now;
		GD.Print("[LobbyManager] Attempting to re-register server after heartbeat rejection");
		RegisterServerInternal(_lastServerRegistration, true);
	}
	
	// Unregister server from lobby
	public async void UnregisterServer()
	{
		if (!_isHosting || string.IsNullOrEmpty(_currentServerId))
			return;
		
		try
		{
			_heartbeatTimer.Stop();
			_isHosting = false;
			
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary { { "server_id", _currentServerId } };
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			await _httpClient.PostAsync($"{ApiUrl}/api/servers/unregister", content);
			
			_currentServerId = "";
			_lastServerRegistration = null;
			GD.Print("[LobbyManager] Server unregistered");
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Unregister failed: {e.Message}");
		}
	}
	
	public async void GetServerList()
	{
		try
		{
			var response = await _httpClient.GetAsync($"{ApiUrl}/api/servers/list");
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("servers"))
					{
						var servers = result["servers"].AsGodotArray();
						EmitSignal(SignalName.ServerListUpdated, servers);
					}
				}
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Get server list failed: {e.Message}");
		}
	}
	
	private string GetPublicIP()
	{
		try
		{
			using (var client = new System.Net.Http.HttpClient())
			{
				return client.GetStringAsync("https://api.ipify.org").Result;
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[LobbyManager] Failed to get Public IP: {e.Message}");
			return "127.0.0.1";
		}
	}
	private string ParseError(string responseText)
	{
		try
		{
			var jsonParser = new Json();
			if (jsonParser.Parse(responseText) == Error.Ok)
			{
				var result = jsonParser.Data.AsGodotDictionary();
				if (result.ContainsKey("error"))
				{
					return result["error"].ToString();
				}
			}
		}
		catch
		{
			// Ignore
		}
		return "Unknown error occurred";
	}

	private static Dictionary CloneDictionary(Dictionary source)
	{
		var copy = new Dictionary();
		if (source == null)
			return copy;
		foreach (var key in source.Keys)
		{
			copy[key] = source[key];
		}
		return copy;
	}

	private static int VariantToInt(Variant value)
	{
		if (value.VariantType == Variant.Type.Int)
			return value.AsInt32();
		if (value.VariantType == Variant.Type.Float)
			return (int)value.AsDouble();
		return int.TryParse(value.ToString(), out var result) ? result : 0;
	}
	
	public override void _ExitTree()
	{
		UnregisterServer();
		_wsCancellation?.Cancel();
		_webSocket?.Dispose();
		_httpClient?.Dispose();
	}
}
