using Godot;
using Godot.Collections;
using System.Linq;

public partial class MainLobbyUI : Control
{
	// Managers
	private AccountManager _accountManager;
	private LobbyManager _lobbyManager;
	private FriendsManager _friendsManager;
	private ChatManager _chatManager;
	private GameManager _gameManager;
	
	// UI Nodes - Login/Register Panel
	[Export] public Control LoginPanel;
	[Export] public LineEdit LoginUsernameInput;
	[Export] public LineEdit LoginPasswordInput;
	[Export] public Button LoginButton;
	[Export] public Button ShowRegisterButton;
	[Export] public Label LoginErrorLabel;
	
	[Export] public Control RegisterPanel;
	[Export] public LineEdit RegisterUsernameInput;
	[Export] public LineEdit RegisterEmailInput;
	[Export] public LineEdit RegisterPasswordInput;
	[Export] public Button RegisterButton;
	[Export] public Button ShowLoginButton;
	[Export] public Label RegisterErrorLabel;
	
	// UI Nodes - Main Lobby
	[Export] public Control MainLobbyPanel;
	[Export] public Label WelcomeLabel;
	[Export] public Button LogoutButton;
	[Export] public TabContainer TabContainer;
	
	// UI Nodes - Server Browser Tab
	[Export] public ItemList ServerList;
	[Export] public Button RefreshServersButton;
	[Export] public Button JoinServerButton;
	[Export] public Button HostServerButton;
	[Export] public LineEdit ServerNameInput;
	[Export] public LineEdit ServerDescInput;
	[Export] public CheckBox PasswordProtectedCheck;
	
	// UI Nodes - Friends Tab
	[Export] public ItemList FriendsList;
	[Export] public ItemList FriendRequestsList;
	[Export] public LineEdit AddFriendInput;
	[Export] public Button AddFriendButton;
	[Export] public Button RemoveFriendButton;
	[Export] public Label FriendsStatusLabel;
	
	// UI Nodes - Chat Tab
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
		// Get managers
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		_lobbyManager = GetNode<LobbyManager>("/root/LobbyManager");
		_friendsManager = GetNode<FriendsManager>("/root/FriendsManager");
		_chatManager = GetNode<ChatManager>("/root/ChatManager");
		_gameManager = GetNode<GameManager>("/root/GameManager");
		
		// Connect signals
		ConnectSignals();
		
		// Setup UI
		SetupUI();
		
		// Check if already logged in
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
		// Account Manager - autoloads are guaranteed to exist
		_accountManager.LoginSuccess += OnLoginSuccess;
		_accountManager.LoginFailed += OnLoginFailed;
		_accountManager.RegisterSuccess += OnRegisterSuccess;
		_accountManager.RegisterFailed += OnRegisterFailed;
		
		// Lobby Manager
		_lobbyManager.ServerListUpdated += OnServerListUpdated;
		_lobbyManager.ServerRegistered += OnServerRegistered;
		_lobbyManager.ServerRegistrationFailed += OnServerRegistrationFailed;
		
		// Friends Manager
		_friendsManager.FriendsListUpdated += OnFriendsListUpdated;
		_friendsManager.FriendRequestsUpdated += OnFriendRequestsUpdated;
		_friendsManager.FriendRequestSent += OnFriendRequestSent;
		_friendsManager.FriendRequestFailed += OnFriendRequestFailed;
		_friendsManager.FriendStatusChanged += OnFriendStatusChanged;
		
		// Chat Manager
		_chatManager.MessageReceived += OnMessageReceived;
		_chatManager.MessageSent += OnMessageSent;
		_chatManager.MessageFailed += OnMessageFailed;
		_chatManager.ChatHistoryLoaded += OnChatHistoryLoaded;
		
		// UI Buttons - null checks to prevent NullReferenceException if nodes not assigned
		if (LoginButton != null) LoginButton.Pressed += OnLoginButtonPressed;
		if (RegisterButton != null) RegisterButton.Pressed += OnRegisterButtonPressed;
		if (ShowRegisterButton != null) ShowRegisterButton.Pressed += ShowRegister;
		if (ShowLoginButton != null) ShowLoginButton.Pressed += ShowLogin;
		if (LogoutButton != null) LogoutButton.Pressed += OnLogoutButtonPressed;
		
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
	
	private void SetupUI()
	{
		// Hide all panels initially
		if (LoginPanel != null) LoginPanel.Hide();
		if (RegisterPanel != null) RegisterPanel.Hide();
		if (MainLobbyPanel != null) MainLobbyPanel.Hide();
	}
	
	// ============ LOGIN/REGISTER ============
	
	private void ShowLogin()
	{
		if (LoginPanel != null) LoginPanel.Show();
		if (RegisterPanel != null) RegisterPanel.Hide();
		if (MainLobbyPanel != null) MainLobbyPanel.Hide();
		if (LoginErrorLabel != null) LoginErrorLabel.Text = "";
	}
	
	private void ShowRegister()
	{
		if (LoginPanel != null) LoginPanel.Hide();
		if (RegisterPanel != null) RegisterPanel.Show();
		if (MainLobbyPanel != null) MainLobbyPanel.Hide();
		if (RegisterErrorLabel != null) RegisterErrorLabel.Text = "";
	}
	
	private void ShowMainLobby()
	{
		if (LoginPanel != null) LoginPanel.Hide();
		if (RegisterPanel != null) RegisterPanel.Hide();
		if (MainLobbyPanel != null) MainLobbyPanel.Show();
		
		var username = _accountManager.GetUsername();
		if (WelcomeLabel != null)
			WelcomeLabel.Text = $"Welcome, {username}!";
		
		// Load initial data
		_lobbyManager.GetServerList();
		_friendsManager.RefreshFriendsList();
		_friendsManager.RefreshPendingRequests();
	}
	
	private void OnLoginButtonPressed()
	{
		var username = LoginUsernameInput?.Text ?? "";
		var password = LoginPasswordInput?.Text ?? "";
		
		if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
		{
			if (LoginErrorLabel != null)
				LoginErrorLabel.Text = "Please enter username and password";
			return;
		}
		
		_accountManager.Login(username, password);
	}
	
	private void OnRegisterButtonPressed()
	{
		var username = RegisterUsernameInput?.Text ?? "";
		var email = RegisterEmailInput?.Text ?? "";
		var password = RegisterPasswordInput?.Text ?? "";
		
		if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
		{
			if (RegisterErrorLabel != null)
				RegisterErrorLabel.Text = "All fields are required";
			return;
		}
		
		_accountManager.Register(username, email, password);
	}
	
	private void OnLoginSuccess(Dictionary userData, string token)
	{
		GD.Print("[MainLobbyUI] Login successful");
		ShowMainLobby();
	}
	
	private void OnLoginFailed(string error)
	{
		if (LoginErrorLabel != null)
			LoginErrorLabel.Text = error;
	}
	
	private void OnRegisterSuccess(Dictionary userData, string token)
	{
		GD.Print("[MainLobbyUI] Registration successful");
		ShowMainLobby();
	}
	
	private void OnRegisterFailed(string error)
	{
		if (RegisterErrorLabel != null)
			RegisterErrorLabel.Text = error;
	}
	
	private void OnLogoutButtonPressed()
	{
		_accountManager.Logout();
		ShowLogin();
	}
	
	// ============ SERVER BROWSER ============
	
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
			var name = server["name"].ToString();
			var players = $"{server["current_players"]}/{server["max_players"]}";
			var map = server["map"].ToString();
			var host = server["host_username"].ToString();
			var locked = (bool)server["password_protected"] ? "🔒 " : "";
			
			ServerList.AddItem($"{locked}{name} - {players} - {map} - Host: {host}");
		}
	}
	
	private void OnServerSelected(long index)
	{
		_selectedServerId = (int)index;
	}
	
	private void OnJoinServerPressed()
	{
		if (_selectedServerId < 0 || _selectedServerId >= _servers.Count)
		{
			GD.PrintErr("[MainLobbyUI] No server selected");
			return;
		}
		
		var server = (Dictionary)_servers[_selectedServerId];
		var ip = server["ip_address"].ToString();
		var port = VariantToInt(server["port"]);
		
		GD.Print($"[MainLobbyUI] Joining server at {ip}:{port}");
		
		// Hide lobby and join game
		Hide();
		_gameManager.JoinGame(ip, port);
	}
	
	private void OnHostServerPressed()
	{
		var serverInfo = new Dictionary
		{
			{ "name", ServerNameInput?.Text ?? "GodotStation Server" },
			{ "description", ServerDescInput?.Text ?? "" },
			{ "password_protected", PasswordProtectedCheck?.ButtonPressed ?? false }
		};
		
		// Start hosting
		_gameManager.HostGame();
		
		// Register in lobby
		_lobbyManager.RegisterServer(serverInfo);
		
		// Hide lobby
		Hide();
	}
	
	private void OnServerRegistered(string serverId)
	{
		GD.Print($"[MainLobbyUI] Server registered: {serverId}");
	}
	
	private void OnServerRegistrationFailed(string error)
	{
		GD.PrintErr($"[MainLobbyUI] Server registration failed: {error}");
	}
	
	// ============ FRIENDS ============
	
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
		
		// Update chat friends list
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
		// Refresh friends list to show online status
		_friendsManager.RefreshFriendsList();
	}
	
	// ============ CHAT ============
	
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
			
			// Load chat history
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
		{
			GD.PrintErr("[MainLobbyUI] No chat friend selected");
			return;
		}
		
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
		
		// If chatting with this person, update chat
		if (senderId == _currentChatFriendId && ChatHistory != null)
		{
			var text = message["message"].ToString();
			var senderName = GetFriendUsername(senderId);
			ChatHistory.AppendText($"[Now] {senderName}: {text}\n");
		}
		
		// TODO: Show notification
	}
	
	private void OnMessageFailed(string error)
	{
		GD.PrintErr($"[MainLobbyUI] Message failed: {error}");
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
	
	// Helper to safely convert Variant to int
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
