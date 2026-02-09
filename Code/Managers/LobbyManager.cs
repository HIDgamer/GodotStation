using Godot;
using Godot.Collections;
using System;
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
	[Export] public string ApiUrl = "http://150.136.90.194:3000";
	[Export] public float HeartbeatInterval = 10.0f;
	
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
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		
		// Setup heartbeat timer
		_heartbeatTimer = new Godot.Timer();
		_heartbeatTimer.WaitTime = HeartbeatInterval;
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
		
		try
		{
			_wsCancellation = new CancellationTokenSource();
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
				
				if (result.MessageType == WebSocketMessageType.Text)
				{
					var message = Encoding.UTF8.GetString(buffer, 0, result.Count);
					CallDeferred(MethodName.HandleWebSocketMessage, message);
				}
			}
			catch (System.Exception e)
			{
				GD.PrintErr($"[LobbyManager] WebSocket error: {e.Message}");
				break;
			}
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
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Error handling WebSocket message: {e.Message}");
		}
	}
	
	// Register server in lobby
	public async void RegisterServer(Dictionary serverInfo)
	{
		if (!_accountManager.IsLoggedIn())
		{
			EmitSignal(SignalName.ServerRegistrationFailed, "Not logged in");
			return;
		}
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			// Get server info from GameManager if not provided
			var gameManager = GetNode<GameManager>("/root/GameManager");
			
			var data = new Dictionary
			{
				{ "name", serverInfo.ContainsKey("name") ? serverInfo["name"].ToString() : "GodotStation Server" },
				{ "map", serverInfo.ContainsKey("map") ? serverInfo["map"].ToString() : gameManager.CurrentMap },
				{ "gamemode", serverInfo.ContainsKey("gamemode") ? serverInfo["gamemode"].ToString() : gameManager.Gamemode },
				{ "max_players", serverInfo.ContainsKey("max_players") ? (int)serverInfo["max_players"] : gameManager.MaxPlayers },
				{ "current_players", serverInfo.ContainsKey("current_players") ? (int)serverInfo["current_players"] : gameManager.PlayerCount },
				{ "port", serverInfo.ContainsKey("port") ? (int)serverInfo["port"] : gameManager.DefaultPort },
				{ "ip_address", serverInfo.ContainsKey("ip_address") ? serverInfo["ip_address"].ToString() : GetPublicIP() },
				{ "password_protected", serverInfo.ContainsKey("password_protected") && (bool)serverInfo["password_protected"] },
				{ "description", serverInfo.ContainsKey("description") ? serverInfo["description"].ToString() : "" }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
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
			}
		}
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.ServerRegistrationFailed, errorMsg);
			GD.PrintErr($"[LobbyManager] {errorMsg}");
		}
	}
	
	// Send heartbeat to keep server alive in lobby
	private async void SendHeartbeat()
	{
		if (!_isHosting || string.IsNullOrEmpty(_currentServerId))
			return;
		
		try
		{
			var gameManager = GetNode<GameManager>("/root/GameManager");
			
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary
			{
				{ "server_id", _currentServerId },
				{ "current_players", gameManager.PlayerCount }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			await _httpClient.PostAsync($"{ApiUrl}/api/servers/heartbeat", content);
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Heartbeat failed: {e.Message}");
		}
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
			GD.Print("[LobbyManager] Server unregistered");
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[LobbyManager] Unregister failed: {e.Message}");
		}
	}
	
	// Get server list from API
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
	
	// Get public IP (simplified - you may want to use a service like ipify.org)
	private string GetPublicIP()
	{
		// For local testing, return localhost
		// In production, you should get the actual public IP
		return "127.0.0.1";
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
	
	public override void _ExitTree()
	{
		UnregisterServer();
		_wsCancellation?.Cancel();
		_webSocket?.Dispose();
		_httpClient?.Dispose();
	}
}
