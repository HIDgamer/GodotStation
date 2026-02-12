using Godot;
using Godot.Collections;

public partial class MainLobbyUI : Control
{
	private AccountManager _accountManager;
	private LobbyManager _lobbyManager;
	private FriendsManager _friendsManager;
	private ChatManager _chatManager;
	private GameManager _gameManager;
	private DiscordRPC _discordRPC;
	[Export] public LineEdit ServerPortInput;
	[Export] public Control LoginPanel;
	[Export] public Button DiscordLoginButton;
	[Export] public Label LoginStatusLabel;
	
	[Export] public Control MainLobbyPanel;
	[Export] public Label WelcomeLabel;
	[Export] public Button LogoutButton;
	[Export] public TabContainer TabContainer;
	
	[Export] public ItemList ServerList;
	[Export] public Button RefreshServersButton;
	[Export] public Button JoinServerButton;
	[Export] public Button HostServerButton;
	[Export] public LineEdit ServerNameInput;
	[Export] public LineEdit ServerDescInput;
	[Export] public CheckBox PasswordProtectedCheck;
	
	[Export] public ItemList FriendsList;
	[Export] public ItemList FriendRequestsList;
	[Export] public LineEdit AddFriendInput;
	[Export] public Button AddFriendButton;
	[Export] public Button RemoveFriendButton;
	[Export] public Label FriendsStatusLabel;
	
	[Export] public ItemList ChatFriendsList;
	[Export] public RichTextLabel ChatHistory;
	[Export] public LineEdit ChatMessageInput;
	[Export] public Button SendMessageButton;
	[Export] public Label ChatWithLabel;

	private Label _welcomeGlow;
	private AnimationPlayer _welcomeGlowAnimation;
	
	private int _selectedServerId = -1;
	private int _selectedFriendId = -1;
	private int _currentChatFriendId = -1;
	private Array _servers = new();
	
	public override void _Ready()
	{
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		_lobbyManager = GetNode<LobbyManager>("/root/LobbyManager");
		_friendsManager = GetNode<FriendsManager>("/root/FriendsManager");
		_chatManager = GetNode<ChatManager>("/root/ChatManager");
		_gameManager = GetNode<GameManager>("/root/GameManager");
		_discordRPC = GetNode<DiscordRPC>("/root/DiscordRpc");
		
		ConnectSignals();
		
		if (_accountManager.IsLoggedIn())
		{
			ShowMainLobby();
		}
		else
		{
			ShowLogin();
		}
	}
	
	private void ConnectSignals()
	{
		_accountManager.LoginSuccess += OnLoginSuccess;
		_accountManager.LoginFailed += OnLoginFailed;
		_accountManager.LoggedOutSuccess += OnLogout;
		
		_lobbyManager.ServerListUpdated += OnServerListUpdated;
		_lobbyManager.ServerRegistered += OnServerRegistered;
		
		_friendsManager.FriendsListUpdated += OnFriendsListUpdated;
		_friendsManager.FriendRequestsUpdated += OnFriendRequestsUpdated;
		_friendsManager.FriendRequestSent += OnFriendRequestSent;
		_friendsManager.FriendRequestFailed += OnFriendRequestFailed;
		_friendsManager.FriendStatusChanged += OnFriendStatusChanged;
		
		_chatManager.MessageReceived += OnMessageReceived;
		_chatManager.MessageSent += OnMessageSent;
		_chatManager.MessageFailed += OnChatMessageFailed;
		_chatManager.ChatHistoryLoaded += OnChatHistoryLoaded;
		
		if (DiscordLoginButton != null) DiscordLoginButton.Pressed += OnDiscordLoginPressed;
		if (LogoutButton != null) LogoutButton.Pressed += OnLogoutPressed;
		
		if (RefreshServersButton != null) RefreshServersButton.Pressed += OnRefreshServersPressed;
		if (JoinServerButton != null) JoinServerButton.Pressed += OnJoinServerPressed;
		if (HostServerButton != null) HostServerButton.Pressed += OnHostServerPressed;
		
		if (AddFriendButton != null) AddFriendButton.Pressed += OnAddFriendPressed;
		if (AddFriendInput != null) AddFriendInput.TextSubmitted += OnAddFriendTextSubmitted;
		if (RemoveFriendButton != null) RemoveFriendButton.Pressed += OnRemoveFriendPressed;
		
		if (SendMessageButton != null) SendMessageButton.Pressed += OnSendMessagePressed;
		if (ChatMessageInput != null) ChatMessageInput.TextSubmitted += OnChatTextSubmitted;
		
		if (ServerList != null) ServerList.ItemSelected += OnServerSelected;
		if (ServerList != null) ServerList.ItemActivated += OnServerActivated;
		if (FriendsList != null) FriendsList.ItemSelected += OnFriendSelected;
		if (FriendRequestsList != null) FriendRequestsList.ItemActivated += OnFriendRequestActivated;
		if (ChatFriendsList != null) ChatFriendsList.ItemSelected += OnChatFriendSelected;
	}
	
	private void ShowLogin()
	{
		if (LoginPanel != null) LoginPanel.Show();
		if (MainLobbyPanel != null) MainLobbyPanel.Hide();
		if (LoginStatusLabel != null) LoginStatusLabel.Text = "";
	}
	
	private void ShowMainLobby()
	{
		if (LoginPanel != null) LoginPanel.Hide();
		if (MainLobbyPanel != null) MainLobbyPanel.Show();
		UpdateWelcomeHeader();
		
		_discordRPC?.SetInLobby();
		
		_lobbyManager.GetServerList();
		_friendsManager.RefreshFriendsList();
		_friendsManager.RefreshPendingRequests();
	}

	private void UpdateWelcomeHeader()
	{
		var tag = _accountManager?.GetDiscordTag();
		if (string.IsNullOrWhiteSpace(tag))
			tag = _accountManager?.GetUsername();
		if (string.IsNullOrWhiteSpace(tag))
			tag = "Player";

		var welcomeText = $"Welcome, {tag}!";
		if (WelcomeLabel != null)
			WelcomeLabel.Text = welcomeText;

		ResolveWelcomeGlowNodes();
		if (_welcomeGlow == null)
			return;

		_welcomeGlow.Text = welcomeText;
		var glowColor = BuildGlowColorFromTag(tag);
		_welcomeGlow.Modulate = new Color(glowColor.R, glowColor.G, glowColor.B, 0.35f);
		ApplyGlowAnimationColor(glowColor);
	}

	private void ResolveWelcomeGlowNodes()
	{
		if (WelcomeLabel == null)
			return;
		_welcomeGlow ??= WelcomeLabel.GetNodeOrNull<Label>("WelcomeGlow");
		_welcomeGlowAnimation ??= _welcomeGlow?.GetNodeOrNull<AnimationPlayer>("AnimationPlayer");
	}

	private static Color BuildGlowColorFromTag(string tag)
	{
		unchecked
		{
			uint hash = 2166136261;
			foreach (char c in tag)
			{
				hash ^= char.ToLowerInvariant(c);
				hash *= 16777619;
			}

			float hue = (hash % 360) / 360.0f;
			float saturation = 0.55f + (((hash >> 8) & 0xFF) / 255.0f) * 0.30f;
			float value = 0.85f + (((hash >> 16) & 0xFF) / 255.0f) * 0.15f;
			return Color.FromHsv(hue, Mathf.Clamp(saturation, 0.55f, 0.85f), Mathf.Clamp(value, 0.85f, 1.0f));
		}
	}

	private void ApplyGlowAnimationColor(Color baseColor)
	{
		if (_welcomeGlowAnimation == null)
			return;

		var anim = _welcomeGlowAnimation.GetAnimation("glow");
		if (anim != null && anim.GetTrackCount() > 0)
		{
			int track = 0;
			int keyCount = anim.TrackGetKeyCount(track);
			for (int i = 0; i < keyCount; i++)
			{
				var keyValue = anim.TrackGetKeyValue(track, i);
				var alpha = keyValue.VariantType == Variant.Type.Color ? keyValue.AsColor().A : 0.5f;
				anim.TrackSetKeyValue(track, i, new Color(baseColor.R, baseColor.G, baseColor.B, alpha));
			}
		}

		_welcomeGlowAnimation.Play("glow");
	}
	
	private void OnDiscordLoginPressed()
	{
		if (LoginStatusLabel != null)
			LoginStatusLabel.Text = "Opening Discord in browser...";
		
		_accountManager.StartDiscordLogin();
	}
	
	private void OnLoginSuccess(Dictionary userData, string token)
	{
		ShowMainLobby();
	}
	
	private void OnLoginFailed(string error)
	{
		if (LoginStatusLabel != null)
			LoginStatusLabel.Text = $"Login failed: {error}";
	}
	
	private void OnLogout()
	{
		ShowLogin();
	}
	
private void OnLogoutPressed()
{
	_accountManager.RequestLogout(); 
}
	private void OnRefreshServersPressed()
	{
		_lobbyManager.GetServerList();
	}
	
	private void OnServerListUpdated(Array servers)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(ServerList))
			return;

		_servers = servers;
		
		ServerList.Clear();
		
		foreach (Dictionary server in servers)
		{
			string name = GetVal(server, "name", "Unknown Server");
			string players = $"{GetVal(server, "current_players", "0")}/{GetVal(server, "max_players", "0")}";
			string map = GetVal(server, "map", "Unknown Map");
			string host = GetVal(server, "host_username", "Unknown Host");
			
			bool isLocked = server.ContainsKey("password_protected") && (bool)server["password_protected"];
			string lockedPrefix = isLocked ? "LOCK " : "";
			
			ServerList.AddItem($"{lockedPrefix}{name} - {players} - {map} - Host: {host}");
		}
	}
	private string GetVal(Dictionary dict, string key, string defaultVal)
	{
		return dict.ContainsKey(key) ? dict[key].ToString() : defaultVal;
	}
	private void OnServerSelected(long index)
	{
		_selectedServerId = (int)index;
	}

	private void OnServerActivated(long index)
	{
		_selectedServerId = (int)index;
		OnJoinServerPressed();
	}
	
	private void OnJoinServerPressed()
	{
		if (_selectedServerId < 0 || _selectedServerId >= _servers.Count)
			return;
		
		var server = (Dictionary)_servers[_selectedServerId];
		var ip = GetServerAddress(server);
		var port = VariantToInt(server.ContainsKey("port") ? server["port"] : 7777);
		var name = server["name"].ToString();
		var currentPlayers = VariantToInt(server["current_players"]);
		var maxPlayers = VariantToInt(server["max_players"]);
		
		Hide();
		_gameManager.JoinGame(ip, port);
		_discordRPC?.SetInGame(name, currentPlayers, maxPlayers);
	}
	
	private void OnHostServerPressed()
	{
		var name = ServerNameInput?.Text ?? "GodotStation Server";
		
		if (!int.TryParse(ServerPortInput?.Text, out int port))
		{
			port = 7777;
		}

		var serverInfo = new Dictionary
		{
			{ "name", name },
			{ "map", "Station" },
			{ "port", port },
			{ "password_protected", PasswordProtectedCheck?.ButtonPressed ?? false },
			{ "description", ServerDescInput?.Text ?? "" }
		};
		
		_gameManager.HostGame(port); 
		
		_lobbyManager.RegisterServer(serverInfo);
		Hide();
	}	
private void OnServerRegistered(string serverId)
	{
		GD.Print($"[MainLobbyUI] Server registered: {serverId}");
	}
	
	private void OnFriendsListUpdated(Array friends)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(FriendsList))
			return;
		
		FriendsList.Clear();
		
		foreach (Dictionary friend in friends)
		{
			var username = friend["username"].ToString();
			var online = friend.ContainsKey("online") && (bool)friend["online"] ? "ONLINE" : "OFFLINE";
			FriendsList.AddItem($"{online} {username}");
		}
		
		if (GodotObject.IsInstanceValid(ChatFriendsList))
		{
			ChatFriendsList.Clear();
			foreach (Dictionary friend in friends)
			{
				var username = friend["username"].ToString();
				ChatFriendsList.AddItem(username);
			}
		}
	}
	
	private void OnFriendRequestsUpdated(Array requests)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(FriendRequestsList))
			return;
		
		FriendRequestsList.Clear();
		
		foreach (Dictionary request in requests)
		{
			var username = request["username"].ToString();
			FriendRequestsList.AddItem($"{username} wants to be friends (Click to accept)");
		}
	}
	
	private void OnFriendSelected(long index)
	{
		var friends = _friendsManager.GetFriendsList();
		if (index >= 0 && index < friends.Count)
		{
			var friend = (Dictionary)friends[(int)index];
			_selectedFriendId = GetUserIdFromDictionary(friend);
		}
	}
	
	private void OnFriendRequestActivated(long index)
	{
		var requests = _friendsManager.GetPendingRequests();
		if (index >= 0 && index < requests.Count)
		{
			var request = (Dictionary)requests[(int)index];
			var userId = GetUserIdFromDictionary(request);
			_friendsManager.AcceptFriendRequest(userId);
		}
	}
	
	private void OnAddFriendPressed()
	{
		var username = (AddFriendInput?.Text ?? "").Trim();
		if (string.IsNullOrEmpty(username))
			return;
		
		_friendsManager.SendFriendRequest(username);
		if (AddFriendInput != null)
			AddFriendInput.Text = "";
	}

	private void OnAddFriendTextSubmitted(string text)
	{
		OnAddFriendPressed();
	}
	
	private void OnRemoveFriendPressed()
	{
		if (_selectedFriendId <= 0)
		{
			if (FriendsStatusLabel != null)
				FriendsStatusLabel.Text = "Please select a friend to remove";
			return;
		}
		
		_friendsManager.RemoveFriend(_selectedFriendId);
		_selectedFriendId = -1;
	}
	
	private void OnFriendRequestSent()
	{
		if (FriendsStatusLabel != null)
			FriendsStatusLabel.Text = "Friend request sent!";
	}
	
	private void OnFriendRequestFailed(string error)
	{
		if (FriendsStatusLabel != null)
			FriendsStatusLabel.Text = $"Error: {error}";
	}
	
	private void OnFriendStatusChanged(int userId, bool online)
	{
		_friendsManager.RefreshFriendsList();
	}
	
	private void OnChatFriendSelected(long index)
	{
		var friends = _friendsManager.GetFriendsList();
		if (index >= 0 && index < friends.Count)
		{
			var friend = (Dictionary)friends[(int)index];
			_currentChatFriendId = GetUserIdFromDictionary(friend);
			var username = friend["username"].ToString();
			
			if (ChatWithLabel != null)
				ChatWithLabel.Text = $"Chat with {username}";
			
			_chatManager.LoadChatHistory(_currentChatFriendId);
		}
	}
	
	private void OnChatHistoryLoaded(int friendId, Array messages)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (friendId != _currentChatFriendId || !GodotObject.IsInstanceValid(ChatHistory))
			return;
		
		ChatHistory.Clear();
		
		foreach (Dictionary msg in messages)
		{
			var senderId = VariantToInt(msg["sender_id"]);
			var message = msg["message"].ToString();
			var timestamp = msg["created_at"].ToString();
			
			var isMe = senderId == _accountManager.GetUserId();
			var sender = isMe ? "You" : GetFriendUsername(senderId);
			
			ChatHistory.AppendText($"[{timestamp}] {sender}: {message}\n");
		}
	}
	
	private void OnSendMessagePressed()
	{
		SendChatMessage();
	}
	
	private void OnChatTextSubmitted(string text)
	{
		SendChatMessage();
	}
	
	private void SendChatMessage()
	{
		if (_currentChatFriendId <= 0)
		{
			if (FriendsStatusLabel != null)
				FriendsStatusLabel.Text = "Select a friend in the Chat tab before sending.";
			return;
		}
		
		var message = (ChatMessageInput?.Text ?? "").Trim();
		if (string.IsNullOrEmpty(message))
			return;
		
		_chatManager.SendMessage(_currentChatFriendId, message);
		
		if (ChatMessageInput != null)
			ChatMessageInput.Text = "";
	}
	
	private void OnMessageSent(Dictionary message)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		var receiverId = VariantToInt(message["receiver_id"]);
		if (receiverId == _currentChatFriendId && GodotObject.IsInstanceValid(ChatHistory))
		{
			var text = message["message"].ToString();
			ChatHistory.AppendText($"[Now] You: {text}\n");
		}
	}
	
	private void OnMessageReceived(Dictionary message)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		var senderId = VariantToInt(message["sender_id"]);
		
		if (senderId == _currentChatFriendId && GodotObject.IsInstanceValid(ChatHistory))
		{
			var text = message["message"].ToString();
			var senderName = GetFriendUsername(senderId);
			ChatHistory.AppendText($"[Now] {senderName}: {text}\n");
		}
	}
	
	private string GetFriendUsername(int friendId)
	{
		var friends = _friendsManager.GetFriendsList();
		foreach (Dictionary friend in friends)
		{
			if (GetUserIdFromDictionary(friend) == friendId)
			{
				return friend["username"].ToString();
			}
		}
		return $"User {friendId}";
	}

	private void OnChatMessageFailed(string error)
	{
		if (FriendsStatusLabel != null)
			FriendsStatusLabel.Text = $"Chat error: {error}";
	}

	private int GetUserIdFromDictionary(Dictionary data)
	{
		if (data.ContainsKey("id"))
			return VariantToInt(data["id"]);
		if (data.ContainsKey("user_id"))
			return VariantToInt(data["user_id"]);
		if (data.ContainsKey("friend_id"))
			return VariantToInt(data["friend_id"]);
		return 0;
	}

	private string GetServerAddress(Dictionary server)
	{
		if (server.ContainsKey("connect_ip") && !string.IsNullOrWhiteSpace(server["connect_ip"].ToString()))
			return server["connect_ip"].ToString();
		if (server.ContainsKey("ip_address") && !string.IsNullOrWhiteSpace(server["ip_address"].ToString()))
			return server["ip_address"].ToString();
		if (server.ContainsKey("public_ip") && !string.IsNullOrWhiteSpace(server["public_ip"].ToString()))
			return server["public_ip"].ToString();
		if (server.ContainsKey("host_ip") && !string.IsNullOrWhiteSpace(server["host_ip"].ToString()))
			return server["host_ip"].ToString();
		return "127.0.0.1";
	}
	
	private int VariantToInt(Variant value)
	{
		if (value.VariantType == Variant.Type.Int)
			return value.AsInt32();
		if (value.VariantType == Variant.Type.Float)
			return (int)value.AsDouble();
		if (int.TryParse(value.ToString(), out var result))
			return result;
		return 0;
	}

	public override void _ExitTree()
	{
		if (_accountManager != null)
		{
			_accountManager.LoginSuccess -= OnLoginSuccess;
			_accountManager.LoginFailed -= OnLoginFailed;
			_accountManager.LoggedOutSuccess -= OnLogout;
		}

		if (_lobbyManager != null)
		{
			_lobbyManager.ServerListUpdated -= OnServerListUpdated;
			_lobbyManager.ServerRegistered -= OnServerRegistered;
		}

		if (_friendsManager != null)
		{
			_friendsManager.FriendsListUpdated -= OnFriendsListUpdated;
			_friendsManager.FriendRequestsUpdated -= OnFriendRequestsUpdated;
			_friendsManager.FriendRequestSent -= OnFriendRequestSent;
			_friendsManager.FriendRequestFailed -= OnFriendRequestFailed;
			_friendsManager.FriendStatusChanged -= OnFriendStatusChanged;
		}

		if (_chatManager != null)
		{
			_chatManager.MessageReceived -= OnMessageReceived;
			_chatManager.MessageSent -= OnMessageSent;
			_chatManager.MessageFailed -= OnChatMessageFailed;
			_chatManager.ChatHistoryLoaded -= OnChatHistoryLoaded;
		}
	}
}
