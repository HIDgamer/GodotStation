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
	[Export] public string ApiUrl = "http://150.136.90.194:3000";
	
	[Signal] public delegate void FriendsListUpdatedEventHandler(Array friends);
	[Signal] public delegate void FriendRequestsUpdatedEventHandler(Array requests);
	[Signal] public delegate void FriendRequestSentEventHandler();
	[Signal] public delegate void FriendRequestFailedEventHandler(string error);
	[Signal] public delegate void FriendStatusChangedEventHandler(int userId, bool online);
	
	private HttpClient _httpClient;
	private AccountManager _accountManager;
	private Array _friendsList = new();
	private Array _pendingRequests = new();
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		
		// Refresh friends list periodically
		var refreshTimer = new Godot.Timer();
		refreshTimer.WaitTime = 30.0f;
		refreshTimer.Timeout += RefreshFriendsList;
		AddChild(refreshTimer);
		refreshTimer.Start();
	}
	
	public Array GetFriendsList()
	{
		return _friendsList;
	}
	
	public Array GetPendingRequests()
	{
		return _pendingRequests;
	}
	
	// Get friends list
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
					}
				}
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to get friends list: {e.Message}");
		}
	}
	
	// Get pending friend requests
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
					}
				}
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[FriendsManager] Failed to get pending requests: {e.Message}");
		}
	}
	
	// Send friend request
	public async void SendFriendRequest(string username)
	{
		if (!_accountManager.IsLoggedIn())
		{
			EmitSignal(SignalName.FriendRequestFailed, "Not logged in");
			return;
		}
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary { { "username", username } };
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/friends/request", content);
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				EmitSignal(SignalName.FriendRequestSent);
				GD.Print($"[FriendsManager] Friend request sent to {username}");
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
	
	// Accept friend request
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
	
	// Reject friend request
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
	
	// Remove friend
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
	
	// Handle friend status updates from WebSocket
	public void OnFriendStatusUpdate(int userId, bool online)
	{
		EmitSignal(SignalName.FriendStatusChanged, userId, online);
		
		// Update friend in list
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
			// Ignore
		}
		return "Unknown error occurred";
	}
	
	public override void _ExitTree()
	{
		_httpClient?.Dispose();
	}
}
