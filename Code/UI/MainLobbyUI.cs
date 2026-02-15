using Godot;
using Godot.Collections;
using System.Collections.Generic;

// Forward declaration for AudioManager
public partial class AudioManager : Node { }

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
	private readonly Queue<string> _uiNotificationQueue = new();
	private readonly HashSet<string> _knownFriendKeys = new();
	private readonly HashSet<string> _knownPendingRequestKeys = new();
	private readonly System.Collections.Generic.Dictionary<int, int> _unreadChatByFriend = new();
	private Timer _serverRefreshTimer;
	private Timer _uiNotificationTimer;
	private PanelContainer _uiNotificationPanel;
	private Label _uiNotificationLabel;
	private bool _serverRefreshInFlight = false;
	private bool _friendListInitialized = false;
	private bool _pendingRequestsInitialized = false;
	private long _lastServerRefreshRequestMs = 0;
	private long _serverRefreshInFlightSinceMs = 0;
	private int _unreadFriendRequestCount = 0;
	private int _unreadChatCount = 0;
	private const int MinPort = 1024;
	private const int MaxPort = 65535;
	private const int ServersTabIndex = 0;
	private const int FriendsTabIndex = 1;
	private const int ChatTabIndex = 2;
	private const double AutoServerRefreshIntervalSeconds = 12.0;
	private const double UiNotificationDurationSeconds = 4.0;
	private const long MinServerRefreshIntervalMs = 4000;
	private const long ServerRefreshTimeoutMs = 8000;
	
	public override void _Ready()
	{
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		_lobbyManager = GetNode<LobbyManager>("/root/LobbyManager");
		_friendsManager = GetNode<FriendsManager>("/root/FriendsManager");
		_chatManager = GetNode<ChatManager>("/root/ChatManager");
		_gameManager = GetNode<GameManager>("/root/GameManager");
		_discordRPC = GetNode<DiscordRPC>("/root/DiscordRpc");
		SetupServerRefreshTimer();
		SetupNotificationUi();
		
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
		_lobbyManager.ServerRegistrationFailed += OnServerRegistrationFailed;
		_gameManager.ConnectionFailed += OnConnectionFailed;
		
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
		if (TabContainer != null) TabContainer.TabChanged += OnLobbyTabChanged;
		
		// Add hover sounds for buttons
		AddHoverSounds();
	}
	
	// Audio helper methods
	private void PlayUIClick()
	{
		var audioManager = GetNodeOrNull<AudioManager>("/root/AudioManager");
		if (audioManager != null)
			audioManager.Call("play_ui_click");
	}
	
	private void PlayUIMenuSelection()
	{
		var audioManager = GetNodeOrNull<AudioManager>("/root/AudioManager");
		if (audioManager != null)
			audioManager.Call("play_ui_menu_selection");
	}
	
	private void PlayUIHover()
	{
		var audioManager = GetNodeOrNull<AudioManager>("/root/AudioManager");
		if (audioManager != null)
			audioManager.Call("play_ui_hover");
	}
	
	private void AddHoverSounds()
	{
		// Add hover sounds to main buttons
		if (DiscordLoginButton != null)
			DiscordLoginButton.MouseEntered += PlayUIHover;
		if (LogoutButton != null)
			LogoutButton.MouseEntered += PlayUIHover;
		if (RefreshServersButton != null)
			RefreshServersButton.MouseEntered += PlayUIHover;
		if (JoinServerButton != null)
			JoinServerButton.MouseEntered += PlayUIHover;
		if (HostServerButton != null)
			HostServerButton.MouseEntered += PlayUIHover;
		if (AddFriendButton != null)
			AddFriendButton.MouseEntered += PlayUIHover;
		if (RemoveFriendButton != null)
			RemoveFriendButton.MouseEntered += PlayUIHover;
		if (SendMessageButton != null)
			SendMessageButton.MouseEntered += PlayUIHover;
	}
	
	private void ShowLogin()
	{
		StopServerAutoRefresh();
		ClearUiNotifications();
		ResetSocialNotificationTracking();
		if (LoginPanel != null) LoginPanel.Show();
		if (MainLobbyPanel != null) MainLobbyPanel.Hide();
		if (LoginStatusLabel != null) LoginStatusLabel.Text = "";
	}
	
	private void ShowMainLobby()
	{
		if (LoginPanel != null) LoginPanel.Hide();
		if (MainLobbyPanel != null) MainLobbyPanel.Show();
		ResetSocialNotificationTracking();
		UpdateWelcomeHeader();
		
		_discordRPC?.SetInLobby();
		
		RequestServerListRefresh(true);
		StartServerAutoRefresh();
		_friendsManager.RefreshFriendsList();
		_friendsManager.RefreshPendingRequests();
	}

	private void SetupServerRefreshTimer()
	{
		_serverRefreshTimer = new Timer
		{
			Name = "ServerRefreshTimer",
			WaitTime = AutoServerRefreshIntervalSeconds,
			OneShot = false,
			Autostart = false
		};
		_serverRefreshTimer.Timeout += OnServerAutoRefreshTimeout;
		AddChild(_serverRefreshTimer);
	}

	private void SetupNotificationUi()
	{
		_uiNotificationTimer = new Timer
		{
			Name = "LobbyNotificationTimer",
			WaitTime = UiNotificationDurationSeconds,
			OneShot = true
		};
		_uiNotificationTimer.Timeout += OnUiNotificationTimeout;
		AddChild(_uiNotificationTimer);

		_uiNotificationPanel = new PanelContainer
		{
			Name = "LobbyNotificationPanel",
			Visible = false,
			MouseFilter = MouseFilterEnum.Ignore,
			CustomMinimumSize = new Vector2(360, 64)
		};
		_uiNotificationPanel.SetAnchorsPreset(LayoutPreset.TopRight);
		_uiNotificationPanel.OffsetLeft = -376;
		_uiNotificationPanel.OffsetTop = 18;
		_uiNotificationPanel.OffsetRight = -16;
		_uiNotificationPanel.OffsetBottom = 90;

		var style = new StyleBoxFlat
		{
			BgColor = new Color(0.08f, 0.13f, 0.23f, 0.94f),
			BorderColor = new Color(0.35f, 0.7f, 1.0f, 0.95f),
			BorderWidthLeft = 2,
			BorderWidthTop = 2,
			BorderWidthRight = 2,
			BorderWidthBottom = 2,
			CornerRadiusTopLeft = 10,
			CornerRadiusTopRight = 10,
			CornerRadiusBottomLeft = 10,
			CornerRadiusBottomRight = 10,
			ShadowColor = new Color(0f, 0f, 0f, 0.45f),
			ShadowSize = 4
		};
		_uiNotificationPanel.AddThemeStyleboxOverride("panel", style);

		var margin = new MarginContainer();
		margin.SetAnchorsPreset(LayoutPreset.FullRect);
		margin.AddThemeConstantOverride("margin_left", 12);
		margin.AddThemeConstantOverride("margin_top", 8);
		margin.AddThemeConstantOverride("margin_right", 12);
		margin.AddThemeConstantOverride("margin_bottom", 8);
		_uiNotificationPanel.AddChild(margin);

		_uiNotificationLabel = new Label
		{
			Name = "Message",
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			HorizontalAlignment = HorizontalAlignment.Left,
			VerticalAlignment = VerticalAlignment.Center
		};
		_uiNotificationLabel.AddThemeColorOverride("font_color", new Color(0.9f, 0.96f, 1f, 1f));
		_uiNotificationLabel.AddThemeFontSizeOverride("font_size", 14);
		margin.AddChild(_uiNotificationLabel);

		AddChild(_uiNotificationPanel);
	}

	private void StartServerAutoRefresh()
	{
		if (_serverRefreshTimer == null)
			return;
		if (_serverRefreshTimer.IsStopped())
			_serverRefreshTimer.Start();
	}

	private void StopServerAutoRefresh()
	{
		_serverRefreshTimer?.Stop();
		_serverRefreshInFlight = false;
		_serverRefreshInFlightSinceMs = 0;
	}

	private void OnServerAutoRefreshTimeout()
	{
		RequestServerListRefresh();
	}

	private void RequestServerListRefresh(bool force = false)
	{
		if (_lobbyManager == null)
			return;
		
		var now = (long)Time.GetTicksMsec();
		
		if (_serverRefreshInFlight)
		{
			if (now - _serverRefreshInFlightSinceMs < ServerRefreshTimeoutMs)
				return;
			
			_serverRefreshInFlight = false;
			_serverRefreshInFlightSinceMs = 0;
		}
		
		if (!force && now - _lastServerRefreshRequestMs < MinServerRefreshIntervalMs)
			return;
		
		_serverRefreshInFlight = true;
		_serverRefreshInFlightSinceMs = now;
		_lastServerRefreshRequestMs = now;
		_lobbyManager.GetServerList();
	}

	private void CompleteServerListRefresh()
	{
		_serverRefreshInFlight = false;
		_serverRefreshInFlightSinceMs = 0;
	}

	private void OnLobbyTabChanged(long tab)
	{
		if (tab == FriendsTabIndex)
			_unreadFriendRequestCount = 0;
		if (tab == ChatTabIndex)
		{
			EnsureChatFriendSelection();
			if (GodotObject.IsInstanceValid(ChatMessageInput))
				ChatMessageInput.GrabFocus();
		}
		UpdateTabBadges();
	}

	private void UpdateTabBadges()
	{
		if (!GodotObject.IsInstanceValid(TabContainer))
			return;

		TabContainer.SetTabTitle(ServersTabIndex, "Servers");
		TabContainer.SetTabTitle(
			FriendsTabIndex,
			_unreadFriendRequestCount > 0 ? $"Friends ({_unreadFriendRequestCount})" : "Friends"
		);
		TabContainer.SetTabTitle(
			ChatTabIndex,
			_unreadChatCount > 0 ? $"Chat ({_unreadChatCount})" : "Chat"
		);
	}

	private void RecalculateUnreadChatCount()
	{
		_unreadChatCount = 0;
		foreach (var unread in _unreadChatByFriend.Values)
		{
			_unreadChatCount += unread;
		}
	}

	private void AddUnreadForFriend(int friendId)
	{
		if (friendId <= 0)
			return;

		_unreadChatByFriend[friendId] = _unreadChatByFriend.TryGetValue(friendId, out var unread) ? unread + 1 : 1;
		RecalculateUnreadChatCount();
		RefreshChatFriendListLabels();
		UpdateTabBadges();
	}

	private void ClearUnreadForFriend(int friendId)
	{
		if (friendId <= 0)
			return;

		if (_unreadChatByFriend.Remove(friendId))
		{
			RecalculateUnreadChatCount();
			RefreshChatFriendListLabels();
			UpdateTabBadges();
		}
	}

	private void RefreshChatFriendListLabels()
	{
		if (!GodotObject.IsInstanceValid(ChatFriendsList) || _friendsManager == null)
			return;

		var friends = _friendsManager.GetFriendsList();
		if (friends == null)
			return;

		var selectedFriendId = _currentChatFriendId;
		ChatFriendsList.Clear();

		for (int i = 0; i < friends.Count; i++)
		{
			var friend = (Dictionary)friends[i];
			var username = GetVal(friend, "username", $"User {GetUserIdFromDictionary(friend)}");
			var friendId = GetUserIdFromDictionary(friend);
			if (_unreadChatByFriend.TryGetValue(friendId, out var unread) && unread > 0)
				ChatFriendsList.AddItem($"{username} ({unread})");
			else
				ChatFriendsList.AddItem(username);
		}

		var selectedIndex = FindFriendIndexById(friends, selectedFriendId);
		if (selectedIndex >= 0)
			ChatFriendsList.Select(selectedIndex);
	}

	private int FindFriendIndexById(Array friends, int friendId)
	{
		if (friendId <= 0 || friends == null)
			return -1;

		for (int i = 0; i < friends.Count; i++)
		{
			var friend = (Dictionary)friends[i];
			if (GetUserIdFromDictionary(friend) == friendId)
				return i;
		}

		return -1;
	}

	private void EnsureChatFriendSelection()
	{
		if (_friendsManager == null)
			return;

		var friends = _friendsManager.GetFriendsList();
		if (friends == null || friends.Count == 0)
		{
			_currentChatFriendId = -1;
			if (GodotObject.IsInstanceValid(ChatWithLabel))
				ChatWithLabel.Text = "Select a friend to chat";
			if (GodotObject.IsInstanceValid(ChatHistory))
				ChatHistory.Clear();
			return;
		}

		var selectedIndex = FindFriendIndexById(friends, _currentChatFriendId);
		if (selectedIndex >= 0)
		{
			if (GodotObject.IsInstanceValid(ChatFriendsList))
				ChatFriendsList.Select(selectedIndex);
			return;
		}

		if (GodotObject.IsInstanceValid(ChatFriendsList))
			ChatFriendsList.Select(0);
		OnChatFriendSelected(0);
	}

	private void EnqueueUiNotification(string message)
	{
		if (string.IsNullOrWhiteSpace(message))
			return;

		_uiNotificationQueue.Enqueue(message.Trim());
		if (!GodotObject.IsInstanceValid(_uiNotificationPanel) || !GodotObject.IsInstanceValid(_uiNotificationLabel))
			return;

		if (!_uiNotificationPanel.Visible)
			ShowNextUiNotification();
	}

	private void ShowNextUiNotification()
	{
		if (!GodotObject.IsInstanceValid(_uiNotificationPanel) || !GodotObject.IsInstanceValid(_uiNotificationLabel))
			return;

		if (_uiNotificationQueue.Count == 0)
		{
			_uiNotificationPanel.Visible = false;
			return;
		}

		_uiNotificationLabel.Text = _uiNotificationQueue.Dequeue();
		_uiNotificationPanel.Visible = true;
		_uiNotificationPanel.MoveToFront();
		_uiNotificationTimer?.Start();
	}

	private void OnUiNotificationTimeout()
	{
		if (_uiNotificationQueue.Count > 0)
		{
			ShowNextUiNotification();
			return;
		}

		if (GodotObject.IsInstanceValid(_uiNotificationPanel))
			_uiNotificationPanel.Visible = false;
	}

	private void ClearUiNotifications()
	{
		_uiNotificationQueue.Clear();
		_uiNotificationTimer?.Stop();
		if (GodotObject.IsInstanceValid(_uiNotificationPanel))
			_uiNotificationPanel.Visible = false;
	}

	private void ResetSocialNotificationTracking()
	{
		_knownFriendKeys.Clear();
		_knownPendingRequestKeys.Clear();
		_unreadChatByFriend.Clear();
		_friendListInitialized = false;
		_pendingRequestsInitialized = false;
		_unreadFriendRequestCount = 0;
		_unreadChatCount = 0;
		UpdateTabBadges();
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
		RequestServerListRefresh(true);
	}
	
	private void OnServerListUpdated(Array servers)
	{
		CompleteServerListRefresh();
		
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(ServerList))
			return;

		_servers = servers;
		
		ServerList.Clear();
		
		foreach (Dictionary server in servers)
		{
			string name = GetVal(server, "name", "Unknown Server");
			
			string currentPlayersStr = "?";
			string maxPlayersStr = "?";
			
			if (server.ContainsKey("current_players"))
			{
				currentPlayersStr = server["current_players"].ToString();
			}
			
			if (server.ContainsKey("max_players"))
			{
				maxPlayersStr = server["max_players"].ToString();
			}
			
			string players = $"{currentPlayersStr}/{maxPlayersStr}";
			string map = GetVal(server, "map", "Unknown Map");
			string host = GetVal(server, "host_username", "Unknown Host");
			
			bool isLocked = server.ContainsKey("password_protected") && (bool)server["password_protected"];
			string lockedPrefix = isLocked ? "🔒 " : "";
			
			GD.Print($"[MainLobbyUI] Server: {name}, current_players={currentPlayersStr}, max_players={maxPlayersStr}");
			
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
		if (!IsValidPort(port))
		{
			SetLobbyStatus($"Invalid server port: {port}. Expected {MinPort}-{MaxPort}.");
			return;
		}

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
			SetLobbyStatus($"Invalid port. Expected {MinPort}-{MaxPort}.");
			return;
		}

		if (!IsValidPort(port))
		{
			SetLobbyStatus($"Invalid port: {port}. Expected {MinPort}-{MaxPort}.");
			return;
		}

		var serverInfo = new Dictionary
		{
			{ "name", name },
			{ "map", "Station" },
			{ "gamemode", "default" },
			{ "max_players", 16 },
			{ "current_players", 0 },
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

	private void OnServerRegistrationFailed(string error)
	{
		SetLobbyStatus($"Server registration failed: {error}");
	}
	
	private void OnFriendsListUpdated(Array friends)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(FriendsList))
			return;

		var nextFriendKeys = new HashSet<string>();
		var newlyAddedFriends = new List<string>();
		var validFriendIds = new HashSet<int>();
		
		FriendsList.Clear();
		
		foreach (Dictionary friend in friends)
		{
			var username = GetVal(friend, "username", $"User {GetUserIdFromDictionary(friend)}");
			var online = friend.ContainsKey("online") && (bool)friend["online"] ? "ONLINE" : "OFFLINE";
			FriendsList.AddItem($"{online} {username}");

			var friendKey = BuildSocialKey(friend);
			var friendId = GetUserIdFromDictionary(friend);
			if (friendId > 0)
				validFriendIds.Add(friendId);
			if (!string.IsNullOrEmpty(friendKey))
			{
				nextFriendKeys.Add(friendKey);
				if (_friendListInitialized && !_knownFriendKeys.Contains(friendKey))
					newlyAddedFriends.Add(username);
			}
		}
		
		if (GodotObject.IsInstanceValid(ChatFriendsList))
		{
			RefreshChatFriendListLabels();
			if (TabContainer != null && TabContainer.CurrentTab == ChatTabIndex)
				EnsureChatFriendSelection();
		}

		_knownFriendKeys.Clear();
		foreach (var key in nextFriendKeys)
			_knownFriendKeys.Add(key);

		var removedUnreadKeys = new List<int>();
		foreach (var friendId in _unreadChatByFriend.Keys)
		{
			if (!validFriendIds.Contains(friendId))
				removedUnreadKeys.Add(friendId);
		}
		foreach (var friendId in removedUnreadKeys)
			_unreadChatByFriend.Remove(friendId);
		RecalculateUnreadChatCount();
		UpdateTabBadges();

		if (FindFriendIndexById(friends, _currentChatFriendId) < 0)
			_currentChatFriendId = -1;

		if (_friendListInitialized)
		{
			foreach (var username in newlyAddedFriends)
			{
				EnqueueUiNotification($"{username} is now your friend.");
			}
		}
		else
		{
			_friendListInitialized = true;
		}
	}
	
	private void OnFriendRequestsUpdated(Array requests)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		if (!GodotObject.IsInstanceValid(FriendRequestsList))
			return;

		var nextPendingKeys = new HashSet<string>();
		var newRequesters = new List<string>();
		
		FriendRequestsList.Clear();
		
		foreach (Dictionary request in requests)
		{
			var username = GetVal(request, "username", $"User {GetUserIdFromDictionary(request)}");
			FriendRequestsList.AddItem($"{username} wants to be friends (Click to accept)");

			var requestKey = BuildSocialKey(request);
			if (!string.IsNullOrEmpty(requestKey))
			{
				nextPendingKeys.Add(requestKey);
				if (_pendingRequestsInitialized && !_knownPendingRequestKeys.Contains(requestKey))
					newRequesters.Add(username);
			}
		}

		_knownPendingRequestKeys.Clear();
		foreach (var key in nextPendingKeys)
			_knownPendingRequestKeys.Add(key);

		if (_pendingRequestsInitialized)
		{
			if (newRequesters.Count > 0)
			{
				foreach (var username in newRequesters)
					EnqueueUiNotification($"Friend request from {username}.");

				if (TabContainer == null || TabContainer.CurrentTab != FriendsTabIndex)
					_unreadFriendRequestCount += newRequesters.Count;

				UpdateTabBadges();
			}
		}
		else
		{
			_pendingRequestsInitialized = true;
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
			EnqueueUiNotification("Friend request accepted.");
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
		EnqueueUiNotification("Friend request sent.");
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
			var username = GetVal(friend, "username", $"User {_currentChatFriendId}");
			
			if (ChatWithLabel != null)
				ChatWithLabel.Text = $"Chat with {username}";

			ClearUnreadForFriend(_currentChatFriendId);
			
			_chatManager.LoadChatHistory(_currentChatFriendId);

			if (GodotObject.IsInstanceValid(ChatMessageInput))
				ChatMessageInput.GrabFocus();
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

		ScrollChatHistoryToBottom();
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
			ScrollChatHistoryToBottom();
		}
	}
	
	private void OnMessageReceived(Dictionary message)
	{
		if (!GodotObject.IsInstanceValid(this) || !IsInsideTree())
			return;
		var senderId = VariantToInt(message["sender_id"]);
		var text = message.ContainsKey("message") ? message["message"].ToString() : "";
		var senderName = GetFriendUsername(senderId);
		var isChatTabActive = TabContainer != null && TabContainer.CurrentTab == ChatTabIndex;
		var isActiveConversation = isChatTabActive && senderId == _currentChatFriendId;

		if (!isActiveConversation)
		{
			if (_accountManager == null || senderId != _accountManager.GetUserId())
			{
				AddUnreadForFriend(senderId);
				var preview = BuildNotificationPreview(text);
				var body = string.IsNullOrEmpty(preview) ? senderName : $"{senderName}: {preview}";
				EnqueueUiNotification($"New chat message from {body}");
			}
		}
		
		if (senderId == _currentChatFriendId && GodotObject.IsInstanceValid(ChatHistory))
		{
			ChatHistory.AppendText($"[Now] {senderName}: {text}\n");
			ScrollChatHistoryToBottom();
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

	private string BuildSocialKey(Dictionary data)
	{
		var id = GetUserIdFromDictionary(data);
		if (id > 0)
			return $"id:{id}";

		var username = GetVal(data, "username", "").Trim().ToLowerInvariant();
		if (!string.IsNullOrEmpty(username))
			return $"username:{username}";

		return "";
	}

	private static string BuildNotificationPreview(string text)
	{
		if (string.IsNullOrWhiteSpace(text))
			return "";

		var normalized = text.Replace("\r", " ").Replace("\n", " ").Trim();
		const int maxLength = 72;
		if (normalized.Length <= maxLength)
			return normalized;

		return $"{normalized.Substring(0, maxLength)}...";
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

	private void ScrollChatHistoryToBottom()
	{
		if (!GodotObject.IsInstanceValid(ChatHistory))
			return;

		var lineCount = ChatHistory.GetLineCount();
		ChatHistory.ScrollToLine(Mathf.Max(0, lineCount - 1));
	}

	private static bool IsValidPort(int port) => port >= MinPort && port <= MaxPort;

	private void OnConnectionFailed()
	{
		SetLobbyStatus("Connection failed. Ensure the server exists and the host port is properly forwarded.");
	}

	private void SetLobbyStatus(string text)
	{
		if (GodotObject.IsInstanceValid(FriendsStatusLabel))
			FriendsStatusLabel.Text = text;
		else if (GodotObject.IsInstanceValid(LoginStatusLabel))
			LoginStatusLabel.Text = text;
	}

	public override void _ExitTree()
	{
		StopServerAutoRefresh();
		ClearUiNotifications();
		if (_uiNotificationTimer != null)
		{
			_uiNotificationTimer.Timeout -= OnUiNotificationTimeout;
			_uiNotificationTimer.Stop();
			_uiNotificationTimer.QueueFree();
			_uiNotificationTimer = null;
		}
		if (_uiNotificationPanel != null)
		{
			_uiNotificationPanel.QueueFree();
			_uiNotificationPanel = null;
		}
		if (_serverRefreshTimer != null)
		{
			_serverRefreshTimer.Timeout -= OnServerAutoRefreshTimeout;
			_serverRefreshTimer.QueueFree();
			_serverRefreshTimer = null;
		}

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
			_lobbyManager.ServerRegistrationFailed -= OnServerRegistrationFailed;
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

		if (_gameManager != null)
		{
			_gameManager.ConnectionFailed -= OnConnectionFailed;
		}

		if (TabContainer != null)
		{
			TabContainer.TabChanged -= OnLobbyTabChanged;
		}
	}
}