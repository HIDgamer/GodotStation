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
		_chatManager.ChatHistoryLoaded += OnChatHistoryLoaded;
		
		if (DiscordLoginButton != null) DiscordLoginButton.Pressed += OnDiscordLoginPressed;
		if (LogoutButton != null) LogoutButton.Pressed += OnLogoutPressed;
		
		if (RefreshServersButton != null) RefreshServersButton.Pressed += OnRefreshServersPressed;
		if (JoinServerButton != null) JoinServerButton.Pressed += OnJoinServerPressed;
		if (HostServerButton != null) HostServerButton.Pressed += OnHostServerPressed;
		
		if (AddFriendButton != null) AddFriendButton.Pressed += OnAddFriendPressed;
		if (RemoveFriendButton != null) RemoveFriendButton.Pressed += OnRemoveFriendPressed;
		
		if (SendMessageButton != null) SendMessageButton.Pressed += OnSendMessagePressed;
		if (ChatMessageInput != null) ChatMessageInput.TextSubmitted += OnChatTextSubmitted;
		
		if (ServerList != null) ServerList.ItemSelected += OnServerSelected;
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
		
		if (WelcomeLabel != null)
			WelcomeLabel.Text = $"Welcome, {_accountManager.GetUsername()}!";
		
		_discordRPC?.SetInLobby();
		
		_lobbyManager.GetServerList();
		_friendsManager.RefreshFriendsList();
		_friendsManager.RefreshPendingRequests();
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
		_servers = servers;
		if (ServerList == null) return;
		
		ServerList.Clear();
		
		foreach (Dictionary server in servers)
		{
			string name = GetVal(server, "name", "Unknown Server");
			string players = $"{GetVal(server, "current_players", "0")}/{GetVal(server, "max_players", "0")}";
			string map = GetVal(server, "map", "Unknown Map");
			string host = GetVal(server, "host_username", "Unknown Host");
			
			bool isLocked = server.ContainsKey("password_protected") && (bool)server["password_protected"];
			string lockedPrefix = isLocked ? "🔒 " : "";
			
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
	
	private void OnJoinServerPressed()
	{
		if (_selectedServerId < 0 || _selectedServerId >= _servers.Count)
			return;
		
		var server = (Dictionary)_servers[_selectedServerId];
		var ip = server["ip_address"].ToString();
		var port = VariantToInt(server["port"]);
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
		if (FriendsList == null) return;
		
		FriendsList.Clear();
		
		foreach (Dictionary friend in friends)
		{
			var username = friend["username"].ToString();
			var online = friend.ContainsKey("online") && (bool)friend["online"] ? "🟢" : "⚫";
			FriendsList.AddItem($"{online} {username}");
		}
		
		if (ChatFriendsList != null)
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
		if (FriendRequestsList == null) return;
		
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
			_selectedFriendId = VariantToInt(friend["id"]);
		}
	}
	
	private void OnFriendRequestActivated(long index)
	{
		var requests = _friendsManager.GetPendingRequests();
		if (index >= 0 && index < requests.Count)
		{
			var request = (Dictionary)requests[(int)index];
			var userId = VariantToInt(request["id"]);
			_friendsManager.AcceptFriendRequest(userId);
		}
	}
	
	private void OnAddFriendPressed()
	{
		var username = AddFriendInput?.Text ?? "";
		if (string.IsNullOrEmpty(username))
			return;
		
		_friendsManager.SendFriendRequest(username);
		if (AddFriendInput != null)
			AddFriendInput.Text = "";
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
			_currentChatFriendId = VariantToInt(friend["id"]);
			var username = friend["username"].ToString();
			
			if (ChatWithLabel != null)
				ChatWithLabel.Text = $"Chat with {username}";
			
			_chatManager.LoadChatHistory(_currentChatFriendId);
		}
	}
	
	private void OnChatHistoryLoaded(int friendId, Array messages)
	{
		if (friendId != _currentChatFriendId || ChatHistory == null)
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
			return;
		
		var message = ChatMessageInput?.Text ?? "";
		if (string.IsNullOrEmpty(message))
			return;
		
		_chatManager.SendMessage(_currentChatFriendId, message);
		
		if (ChatMessageInput != null)
			ChatMessageInput.Text = "";
	}
	
	private void OnMessageSent(Dictionary message)
	{
		var receiverId = VariantToInt(message["receiver_id"]);
		if (receiverId == _currentChatFriendId && ChatHistory != null)
		{
			var text = message["message"].ToString();
			ChatHistory.AppendText($"[Now] You: {text}\n");
		}
	}
	
	private void OnMessageReceived(Dictionary message)
	{
		var senderId = VariantToInt(message["sender_id"]);
		
		if (senderId == _currentChatFriendId && ChatHistory != null)
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
			if (VariantToInt(friend["id"]) == friendId)
			{
				return friend["username"].ToString();
			}
		}
		return $"User {friendId}";
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
}
