using Godot;
using Godot.Collections;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;
using Array = Godot.Collections.Array;

public partial class FriendsManager : Node
{
	[Export] public string ApiUrl = "auth.godostation.com";

	[Signal] public delegate void FriendsListUpdatedEventHandler(Array friends);
	[Signal] public delegate void FriendRequestsUpdatedEventHandler(Array requests);
	[Signal] public delegate void FriendRequestSentEventHandler();
	[Signal] public delegate void FriendRequestFailedEventHandler(string error);
	[Signal] public delegate void FriendStatusChangedEventHandler(int userId, bool online);

	private const string FRIENDS_CACHE_PATH = "user://friends_cache.dat";
	private const string PENDING_CACHE_PATH  = "user://pending_requests_cache.dat";

	private HttpClient _httpClient;
	private AccountManager _accountManager;
	private Array _friendsList      = new();
	private Array _pendingRequests  = new();
	private Godot.Timer _refreshTimer;
	private WebSocketPeer _webSocket;
	private bool _wsConnected = false;
	private bool _wsAuthenticated = false;

	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_httpClient.Timeout = TimeSpan.FromSeconds(10);

		_accountManager = GetNode<AccountManager>("/root/AccountManager");

		_refreshTimer = new Godot.Timer();
		_refreshTimer.WaitTime = 15.0f;
		_refreshTimer.Timeout += OnPeriodicRefresh;
		AddChild(_refreshTimer);
		_refreshTimer.Start();

		_accountManager.LoginSuccess += OnLoginSuccess;
		_accountManager.Logout       += OnLogout;

		LoadCachedData();

		if (_accountManager.IsLoggedIn())
			CallDeferred(MethodName.OnLoginSuccess, new Dictionary(), "");
	}

	private void OnLoginSuccess(Dictionary userData, string token)
	{
		RefreshFriendsList();
		RefreshPendingRequests();
		ConnectWebSocket();
	}

	private void OnLogout()
	{
		SaveCachedData();
		DisconnectWebSocket();
	}

	private void OnPeriodicRefresh()
	{
		RefreshFriendsList();
		RefreshPendingRequests();
	}

	// WebSocket.
	private async void ConnectWebSocket()
	{
		if (!_accountManager.IsLoggedIn() || _wsConnected) return;

		try
		{
			_webSocket = new WebSocketPeer();

			// No ?token= in the URL - token goes in the first message.
			var wsUrl = ApiUrl.Replace("https://", "wss://").Replace("http://", "ws://");
			var error = _webSocket.ConnectToUrl(wsUrl);

			if (error != Error.Ok)
			{
				GD.PrintErr($"[FriendsManager] WS connect failed: {error}");
				return;
			}

			// Wait up to 5 seconds for the connection to open.
			for (int i = 0; i < 50; i++)
			{
				await Task.Delay(100);
				_webSocket.Poll();

				var state = _webSocket.GetReadyState();
				if (state == WebSocketPeer.State.Open)
				{
					_wsConnected = true;
					_wsAuthenticated = false;

					// Send auth token as the first message - never in the url.
					var authMsg = Json.Stringify(new Dictionary
					{
						{ "type",  "auth" },
						{ "token", _accountManager.GetAuthToken() }
					});
					_webSocket.SendText(authMsg);
					GD.Print("[FriendsManager] WS connected, auth message sent");
					return;
				}
				else if (state == WebSocketPeer.State.Closed)
				{
					GD.PrintErr("[FriendsManager] WS connection closed before open");
					return;
				}
			}

			GD.PrintErr("[FriendsManager] WS connection timed out");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] WS connection error: {e.Message}");
		}
	}

	private void DisconnectWebSocket()
	{
		if (_webSocket != null)
		{
			_webSocket.Close();
			_webSocket = null;
			_wsConnected = false;
			_wsAuthenticated = false;
			GD.Print("[FriendsManager] WS disconnected");
		}
	}

	public override void _Process(double delta)
	{
		if (_webSocket == null || !_wsConnected) return;

		_webSocket.Poll();
		var state = _webSocket.GetReadyState();

		if (state == WebSocketPeer.State.Open)
		{
			while (_webSocket.GetAvailablePacketCount() > 0)
			{
				var packet = _webSocket.GetPacket();

				// Reject oversized messages before parsing.
				if (packet.Length > 8192)
				{
					GD.PrintErr("[FriendsManager] WS message too large, ignored");
					continue;
				}

				ProcessWebSocketMessage(Encoding.UTF8.GetString(packet));
			}
		}
		else if (state == WebSocketPeer.State.Closed)
		{
			_wsConnected = false;
			_wsAuthenticated = false;
			GD.Print("[FriendsManager] WS lost, reconnecting...");

			if (_accountManager.IsLoggedIn())
				CallDeferred(MethodName.ConnectWebSocket);
		}
	}

	private void ProcessWebSocketMessage(string message)
	{
		try
		{
			var parser = new Json();
			if (parser.Parse(message) != Error.Ok) return;

			var data = parser.Data.AsGodotDictionary();
			if (!data.ContainsKey("type")) return;

			var type = data["type"].ToString();

			switch (type)
			{
				case "auth_success":
					_wsAuthenticated = true;
					GD.Print("[FriendsManager] WS authenticated");
					break;

				case "auth_error":
					GD.PrintErr("[FriendsManager] WS auth rejected by server, disconnecting");
					DisconnectWebSocket();
					break;

				case "friend_status":
					if (!_wsAuthenticated) break;
					if (data.ContainsKey("user_id") && data.ContainsKey("online"))
					{
						var userId = data["user_id"].AsInt32();
						var online = data["online"].AsBool();
						OnFriendStatusUpdate(userId, online);
					}
					break;

				case "friend_request":
					if (!_wsAuthenticated) break;
					RefreshPendingRequests();
					break;

				case "friend_added":
					if (!_wsAuthenticated) break;
					RefreshFriendsList();
					RefreshPendingRequests();
					break;

				case "friend_removed":
					if (!_wsAuthenticated) break;
					RefreshFriendsList();
					break;
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] WS message error: {e.Message}");
		}
	}

	// Cache (AES-256-GCM via CryptoUtils).

	private void LoadCachedData()
	{
		LoadCache(FRIENDS_CACHE_PATH, out _friendsList, SignalName.FriendsListUpdated, "friends");
		LoadCache(PENDING_CACHE_PATH,  out _pendingRequests, SignalName.FriendRequestsUpdated, "pending");
	}

	private void LoadCache(string path, out Array target, StringName signal, string label)
	{
		target = new Array();
		try
		{
			if (!FileAccess.FileExists(path)) return;
			using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
			if (file == null) return;

			var json = CryptoUtils.Decrypt(file.GetAsText());
			if (string.IsNullOrEmpty(json)) return;

			var parser = new Json();
			if (parser.Parse(json) != Error.Ok) return;

			target = parser.Data.AsGodotArray();
			EmitSignal(signal, target);
			GD.Print($"[FriendsManager] Loaded {target.Count} cached {label}");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to load cache ({label}): {e.Message}");
		}
	}

	private void SaveCachedData()
	{
		SaveCache(FRIENDS_CACHE_PATH,  _friendsList,     "friends");
		SaveCache(PENDING_CACHE_PATH,  _pendingRequests, "pending");
	}

	private void SaveCache(string path, Array data, string label)
	{
		if (data == null || data.Count == 0) return;
		try
		{
			using var file = FileAccess.Open(path, FileAccess.ModeFlags.Write);
			if (file == null) return;
			file.StoreString(CryptoUtils.Encrypt(Json.Stringify(data)));
			GD.Print($"[FriendsManager] Saved {data.Count} {label} to cache");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to save cache ({label}): {e.Message}");
		}
	}

	// API calls.

	public async void RefreshFriendsList()
	{
		if (!_accountManager.IsLoggedIn()) return;

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");

			var response = await _httpClient.GetAsync($"{ApiUrl}/api/friends");
			var responseText = await response.Content.ReadAsStringAsync();

			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					if (result.ContainsKey("friends"))
					{
						_friendsList = result["friends"].AsGodotArray();
						EmitSignal(SignalName.FriendsListUpdated, _friendsList);
						SaveCachedData();
					}
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to get friends list: {e.Message}");
		}
	}

	public async void RefreshPendingRequests()
	{
		if (!_accountManager.IsLoggedIn()) return;

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");

			var response = await _httpClient.GetAsync($"{ApiUrl}/api/friends/pending");
			var responseText = await response.Content.ReadAsStringAsync();

			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					if (result.ContainsKey("requests"))
					{
						_pendingRequests = result["requests"].AsGodotArray();
						EmitSignal(SignalName.FriendRequestsUpdated, _pendingRequests);
						SaveCachedData();
					}
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to get pending requests: {e.Message}");
		}
	}

	public async void SendFriendRequest(string username)
	{
		if (!_accountManager.IsLoggedIn())
		{
			EmitSignal(SignalName.FriendRequestFailed, "Not logged in");
			return;
		}

		var identifier = NormalizeFriendIdentifier(username);
		if (string.IsNullOrEmpty(identifier))
		{
			EmitSignal(SignalName.FriendRequestFailed, "Enter a username or Discord tag");
			return;
		}

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");

			var data = new Dictionary
			{
				{ "identifier",  identifier },
				{ "username",    identifier },
				{ "discord_tag", identifier }
			};
			var content = new StringContent(Json.Stringify(data), Encoding.UTF8, "application/json");
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/friends/request", content);
			var responseText = await response.Content.ReadAsStringAsync();

			if (response.IsSuccessStatusCode)
			{
				EmitSignal(SignalName.FriendRequestSent);
				RefreshFriendsList();
				RefreshPendingRequests();
				GD.Print($"[FriendsManager] Friend request sent to {identifier}");
			}
			else
			{
				var error = ParseError(responseText);
				EmitSignal(SignalName.FriendRequestFailed, error);
				GD.PrintErr($"[FriendsManager] Friend request failed: {error}");
			}
		}
		catch (Exception e)
		{
			EmitSignal(SignalName.FriendRequestFailed, $"Connection error: {e.Message}");
			GD.PrintErr($"[FriendsManager] SendFriendRequest: {e.Message}");
		}
	}

	public async void AcceptFriendRequest(int userId)
	{
		if (!_accountManager.IsLoggedIn()) return;

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");

			var content = new StringContent(
				Json.Stringify(new Dictionary { { "user_id", userId }, { "accept", true } }),
				Encoding.UTF8, "application/json");

			var response = await _httpClient.PostAsync($"{ApiUrl}/api/friends/respond", content);

			if (response.IsSuccessStatusCode)
			{
				GD.Print($"[FriendsManager] Accepted request from {userId}");
				RefreshFriendsList();
				RefreshPendingRequests();
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] AcceptFriendRequest: {e.Message}");
		}
	}

	public async void RejectFriendRequest(int userId)
	{
		if (!_accountManager.IsLoggedIn()) return;

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");

			var content = new StringContent(
				Json.Stringify(new Dictionary { { "user_id", userId }, { "accept", false } }),
				Encoding.UTF8, "application/json");

			await _httpClient.PostAsync($"{ApiUrl}/api/friends/respond", content);
			RefreshPendingRequests();
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] RejectFriendRequest: {e.Message}");
		}
	}

	public async void RemoveFriend(int friendId)
	{
		if (!_accountManager.IsLoggedIn()) return;

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			await _httpClient.DeleteAsync($"{ApiUrl}/api/friends/{friendId}");
			RefreshFriendsList();
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] RemoveFriend: {e.Message}");
		}
	}

	public void OnFriendStatusUpdate(int userId, bool online)
	{
		GD.Print($"[FriendsManager] Friend {userId} → {(online ? "online" : "offline")}");

		bool found = false;
		for (int i = 0; i < _friendsList.Count; i++)
		{
			var friend = _friendsList[i].AsGodotDictionary();
			Variant v = friend["id"];

			int friendId = v.VariantType switch
			{
				Variant.Type.Int    => v.AsInt32(),
				Variant.Type.Float  => (int)v.AsSingle(),
				Variant.Type.String => int.TryParse(v.AsString(), out var n) ? n : 0,
				_                   => 0
			};

			if (friendId == userId)
			{
				friend["online"] = online;
				_friendsList[i] = friend;
				found = true;
				break;
			}
		}

		if (found)
		{
			EmitSignal(SignalName.FriendStatusChanged, userId, online);
			EmitSignal(SignalName.FriendsListUpdated, _friendsList);
			SaveCachedData();
		}
	}

	// Helpers.

	public Array GetFriendsList()      => _friendsList;
	public Array GetPendingRequests()  => _pendingRequests;

	private static string NormalizeFriendIdentifier(string raw)
	{
		if (string.IsNullOrWhiteSpace(raw)) return "";
		var value = raw.Trim();
		if (value.StartsWith("@")) value = value.Substring(1);
		return value;
	}

	private static string ParseError(string responseText)
	{
		try
		{
			var parser = new Json();
			if (parser.Parse(responseText) == Error.Ok)
			{
				var result = parser.Data.AsGodotDictionary();
				if (result.ContainsKey("error"))
					return result["error"].ToString();
			}
		}
		catch { }
		return "Unknown error occurred";
	}

	public override void _ExitTree()
	{
		SaveCachedData();
		DisconnectWebSocket();

		if (_accountManager != null)
		{
			_accountManager.LoginSuccess -= OnLoginSuccess;
			_accountManager.Logout       -= OnLogout;
		}

		if (_refreshTimer != null)
		{
			_refreshTimer.Timeout -= OnPeriodicRefresh;
			_refreshTimer.Stop();
			_refreshTimer.QueueFree();
			_refreshTimer = null;
		}

		_httpClient?.Dispose();
	}
}
