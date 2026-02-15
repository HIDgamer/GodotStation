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
	[Export] public string ApiUrl = "https://godotstation.duckdns.org";
	
	[Signal] public delegate void FriendsListUpdatedEventHandler(Array friends);
	[Signal] public delegate void FriendRequestsUpdatedEventHandler(Array requests);
	[Signal] public delegate void FriendRequestSentEventHandler();
	[Signal] public delegate void FriendRequestFailedEventHandler(string error);
	[Signal] public delegate void FriendStatusChangedEventHandler(int userId, bool online);
	
	private const string FRIENDS_CACHE_PATH = "user://friends_cache.dat";
	private const string PENDING_CACHE_PATH = "user://pending_requests_cache.dat";
	
	private HttpClient _httpClient;
	private AccountManager _accountManager;
	private Array _friendsList = new();
	private Array _pendingRequests = new();
	private Godot.Timer _refreshTimer;
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		
		_refreshTimer = new Godot.Timer();
		_refreshTimer.WaitTime = 15.0f;
		_refreshTimer.Timeout += OnPeriodicRefresh;
		AddChild(_refreshTimer);
		_refreshTimer.Start();

		_accountManager.LoginSuccess += OnLoginSuccess;
		_accountManager.Logout += OnLogout;

		LoadCachedData();

		if (_accountManager.IsLoggedIn())
		{
			CallDeferred(MethodName.OnLoginSuccess, new Dictionary(), "");
		}
	}

	private void OnLoginSuccess(Dictionary userData, string token)
	{
		RefreshFriendsList();
		RefreshPendingRequests();
	}
	
	private void OnLogout()
	{
		SaveCachedData();
	}

	private void OnPeriodicRefresh()
	{
		RefreshFriendsList();
		RefreshPendingRequests();
	}
	
	private void LoadCachedData()
	{
		try
		{
			if (FileAccess.FileExists(FRIENDS_CACHE_PATH))
			{
				using var file = FileAccess.Open(FRIENDS_CACHE_PATH, FileAccess.ModeFlags.Read);
				if (file != null)
				{
					var encrypted = file.GetAsText();
					var json = DecryptData(encrypted);
					if (!string.IsNullOrEmpty(json))
					{
						var parser = new Json();
						if (parser.Parse(json) == Error.Ok)
						{
							_friendsList = parser.Data.AsGodotArray();
							EmitSignal(SignalName.FriendsListUpdated, _friendsList);
							GD.Print($"[FriendsManager] Loaded {_friendsList.Count} cached friends");
						}
					}
				}
			}
			
			if (FileAccess.FileExists(PENDING_CACHE_PATH))
			{
				using var file = FileAccess.Open(PENDING_CACHE_PATH, FileAccess.ModeFlags.Read);
				if (file != null)
				{
					var encrypted = file.GetAsText();
					var json = DecryptData(encrypted);
					if (!string.IsNullOrEmpty(json))
					{
						var parser = new Json();
						if (parser.Parse(json) == Error.Ok)
						{
							_pendingRequests = parser.Data.AsGodotArray();
							EmitSignal(SignalName.FriendRequestsUpdated, _pendingRequests);
							GD.Print($"[FriendsManager] Loaded {_pendingRequests.Count} cached requests");
						}
					}
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to load cached data: {e.Message}");
		}
	}
	
	private void SaveCachedData()
	{
		try
		{
			if (_friendsList.Count > 0)
			{
				using var file = FileAccess.Open(FRIENDS_CACHE_PATH, FileAccess.ModeFlags.Write);
				if (file != null)
				{
					var json = Json.Stringify(_friendsList);
					var encrypted = EncryptData(json);
					file.StoreString(encrypted);
					GD.Print($"[FriendsManager] Saved {_friendsList.Count} friends to cache");
				}
			}
			
			if (_pendingRequests.Count > 0)
			{
				using var file = FileAccess.Open(PENDING_CACHE_PATH, FileAccess.ModeFlags.Write);
				if (file != null)
				{
					var json = Json.Stringify(_pendingRequests);
					var encrypted = EncryptData(json);
					file.StoreString(encrypted);
					GD.Print($"[FriendsManager] Saved {_pendingRequests.Count} pending requests to cache");
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to save cached data: {e.Message}");
		}
	}
	
	private string EncryptData(string data)
	{
		const string key = "GSnebula2025";
		var result = new StringBuilder();
		
		for (int i = 0; i < data.Length; i++)
		{
			result.Append((char)(data[i] ^ key[i % key.Length]));
		}
		
		return Convert.ToBase64String(Encoding.UTF8.GetBytes(result.ToString()));
	}
	
	private string DecryptData(string encrypted)
	{
		try
		{
			var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(encrypted));
			const string key = "GSnebula2025";
			var result = new StringBuilder();
			
			for (int i = 0; i < decoded.Length; i++)
			{
				result.Append((char)(decoded[i] ^ key[i % key.Length]));
			}
			
			return result.ToString();
		}
		catch
		{
			return "";
		}
	}
	
	public Array GetFriendsList()
	{
		return _friendsList;
	}
	
	public Array GetPendingRequests()
	{
		return _pendingRequests;
	}
	
	public async void RefreshFriendsList()
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
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
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to get friends list: {e.Message}");
		}
	}
	
	public async void RefreshPendingRequests()
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
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
		catch (System.Exception e)
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
				{ "identifier", identifier },
				{ "username", identifier },
				{ "discord_tag", identifier }
			};
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
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
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.FriendRequestFailed, errorMsg);
			GD.PrintErr($"[FriendsManager] {errorMsg}");
		}
	}
	
	public async void AcceptFriendRequest(int userId)
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary 
			{ 
				{ "user_id", userId }, 
				{ "accept", true } 
			};
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/friends/respond", content);
			
			if (response.IsSuccessStatusCode)
			{
				GD.Print($"[FriendsManager] Accepted friend request from user {userId}");
				RefreshFriendsList();
				RefreshPendingRequests();
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to accept friend request: {e.Message}");
		}
	}
	
	public async void RejectFriendRequest(int userId)
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary 
			{ 
				{ "user_id", userId }, 
				{ "accept", false } 
			};
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/friends/respond", content);
			
			if (response.IsSuccessStatusCode)
			{
				GD.Print($"[FriendsManager] Rejected friend request from user {userId}");
				RefreshPendingRequests();
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to reject friend request: {e.Message}");
		}
	}
	
	public async void RemoveFriend(int friendId)
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var response = await _httpClient.DeleteAsync($"{ApiUrl}/api/friends/{friendId}");
			
			if (response.IsSuccessStatusCode)
			{
				GD.Print($"[FriendsManager] Removed friend {friendId}");
				RefreshFriendsList();
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to remove friend: {e.Message}");
		}
	}
	
	public void OnFriendStatusUpdate(int userId, bool online)
	{
		EmitSignal(SignalName.FriendStatusChanged, userId, online);
		
		foreach (Dictionary friend in _friendsList)
		{
			Variant v = friend["id"];

			int friendId = v.VariantType switch
			{
				Variant.Type.Int => v.AsInt32(),
				Variant.Type.Float => (int)v.AsSingle(),
				Variant.Type.String => int.TryParse(v.AsString(), out var n) ? n : 0,
				_ => 0
			};

			if (friendId == userId)
			{
				friend["online"] = online;
				break;
			}
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
		}
		return "Unknown error occurred";
	}

	private static string NormalizeFriendIdentifier(string raw)
	{
		if (string.IsNullOrWhiteSpace(raw))
			return "";
		var value = raw.Trim();
		if (value.StartsWith("@"))
			value = value.Substring(1);
		return value;
	}
	
	public override void _ExitTree()
	{
		SaveCachedData();
		
		if (_accountManager != null)
		{
			_accountManager.LoginSuccess -= OnLoginSuccess;
			_accountManager.Logout -= OnLogout;
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