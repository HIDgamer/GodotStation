using Godot;
using Godot.Collections;
using System.Linq;

public partial class LateJoinLobbyUI : Control
{
	[Export] public Control PreRoundPanel;
	[Export] public Control LateJoinPanel;
	[Export] public Label StatusLabel;
	[Export] public Label CharacterNameLabel;
	[Export] public Button ReadyButton;
	[Export] public Button UnreadyButton;
	[Export] public Button PreferencesButton;
	[Export] public Button ObserveButton;
	[Export] public Label ReadyCountLabel;
	[Export] public Label TimerLabel;

	[Export] public TabContainer JobTabs;
	[Export] public Button JoinButton;
	[Export] public Label SelectedJobLabel;
	[Export] public RichTextLabel JobDescriptionLabel;
	[Export] public Label ManifestLabel;

	private GameManager _gameManager;
	private JobManager _jobManager;
	private string _selectedJob = "";
	private bool _isReady = false;
	private int _readyPlayerCount = 0;
	private bool _roundStarted = false;
	private Timer _bootTimer;
	private int _bootPhase = 0;

	private System.Collections.Generic.HashSet<int> _readyPeers = new();

	private static readonly string[] BootMessages = {
		">",
		"> .",
		"> ..",
		"> ...",
		"> INITIALIZING TERMINAL...",
		"> CONNECTING TO STATION DATABASE...",
		"> LOADING CREW MANIFEST...",
		"> TERMINAL READY"
	};

	public override void _Ready()
	{
		_gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
		_jobManager = GetNodeOrNull<JobManager>("/root/JobManager");

		if (_jobManager == null)
		{
			_jobManager = new JobManager();
			_jobManager.Name = "JobManager";
			GetTree().Root.CallDeferred("add_child", _jobManager);
		}

		ConnectSignals();
		PlayBootSequence();
		UpdateUI();
	}

	private void PlayBootSequence()
	{
		_bootTimer = new Timer();
		_bootTimer.WaitTime = 0.15f;
		_bootTimer.Timeout += OnBootTimerTimeout;
		AddChild(_bootTimer);
		_bootTimer.Start();

		if (StatusLabel != null)
			StatusLabel.Text = ">";
	}

	private void OnBootTimerTimeout()
	{
		if (_bootPhase < BootMessages.Length)
		{
			if (StatusLabel != null)
				StatusLabel.Text = BootMessages[_bootPhase];
			_bootPhase++;
		}
		else
		{
			_bootTimer.Stop();
			CallDeferred(MethodName.FinalizeBootSequence);
		}
	}

	private void FinalizeBootSequence()
	{
		UpdateCharacterName();
		if (_roundStarted)
			ShowLateJoinPhase();
		else
			UpdateStatusForPreRound();
	}

	private void ConnectSignals()
	{
		if (ReadyButton != null)
			ReadyButton.Pressed += OnReadyPressed;
		if (UnreadyButton != null)
			UnreadyButton.Pressed += OnUnreadyPressed;
		if (PreferencesButton != null)
			PreferencesButton.Pressed += OnPreferencesPressed;
		if (ObserveButton != null)
			ObserveButton.Pressed += OnObservePressed;
		if (JoinButton != null)
			JoinButton.Pressed += OnJoinPressed;

		if (_gameManager != null)
		{
			_gameManager.GameStarted += OnGameStarted;
			_gameManager.PlayersUpdated += UpdateReadyCount;
			_gameManager.RoundEnded += OnRoundEnded;
		}

		if (_jobManager != null)
			_jobManager.JobAvailabilityChanged += RefreshJobList;
	}

	private bool IsMultiplayerConnected()
	{
		var peer = Multiplayer.MultiplayerPeer;
		if (peer == null) return false;
		if (Multiplayer.IsServer()) return true;
		return peer.GetConnectionStatus() == MultiplayerPeer.ConnectionStatus.Connected;
	}

	private void OnRoundEnded()
	{
		_roundStarted = false;
		_isReady = false;
		_readyPeers.Clear();
		_readyPlayerCount = 0;
		_selectedJob = "";

		if (PreferencesButton != null)
			PreferencesButton.Disabled = false;

		ShowPreRoundPhase();
		UpdateStatusForPreRound();
	}

	private void UpdateCharacterName()
	{
		if (CharacterNameLabel == null) return;

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		if (prefManager != null && prefManager.HasMethod("get_character_data"))
		{
			var charData = (Dictionary)prefManager.Call("get_character_data");
			if (charData != null && charData.ContainsKey("name"))
			{
				CharacterNameLabel.Text = $"> OPERATOR: {charData["name"].ToString().ToUpper()}";
				return;
			}
		}
		CharacterNameLabel.Text = "> OPERATOR: UNKNOWN";
	}

	private void UpdateUI()
	{
		bool gameStarted = _gameManager?.IsGameRunning() ?? false;
		_roundStarted = gameStarted;

		if (gameStarted)
		{
			ShowLateJoinPhase();
		}
		else
		{
			ShowPreRoundPhase();
			UpdateReadyCount();
		}
	}

	private void ShowPreRoundPhase()
	{
		if (PreRoundPanel != null)
			PreRoundPanel.Visible = true;
		if (LateJoinPanel != null)
			LateJoinPanel.Visible = false;
		UpdateReadyButtons();
	}

	private void ShowLateJoinPhase()
	{
		if (PreRoundPanel != null)
			PreRoundPanel.Visible = false;
		if (LateJoinPanel != null)
			LateJoinPanel.Visible = true;
		if (JoinButton != null)
			JoinButton.Disabled = true;
		if (PreferencesButton != null)
			PreferencesButton.Disabled = true;

		RefreshJobList();
		UpdateStatusForLateJoin();
	}

	private void OnReadyPressed()
	{
		if (!IsMultiplayerConnected())
		{
			if (StatusLabel != null)
				StatusLabel.Text = "> ERROR: NOT CONNECTED";
			return;
		}

		_isReady = true;

		if (Multiplayer.IsServer())
		{
			_readyPeers.Add(1);
			_readyPlayerCount = _readyPeers.Count;
			UpdateReadyCount();
		}
		else
		{
			var rpcErr = RpcId(1, MethodName.ServerSetReady, Multiplayer.GetUniqueId(), true);
			if (rpcErr != Error.Ok)
			{
				_isReady = false;
				if (StatusLabel != null)
					StatusLabel.Text = "> ERROR: READY RPC FAILED";
			}
		}

		UpdateReadyButtons();
		if (StatusLabel != null)
			StatusLabel.Text = "> STATUS: READY [AWAITING ROUND START]";
	}

	private void OnUnreadyPressed()
	{
		if (!Multiplayer.IsServer() && !IsMultiplayerConnected())
		{
			if (StatusLabel != null)
				StatusLabel.Text = "> ERROR: NOT CONNECTED";
			return;
		}

		_isReady = false;

		if (Multiplayer.IsServer())
		{
			_readyPeers.Remove(1);
			_readyPlayerCount = _readyPeers.Count;
			UpdateReadyCount();
		}
		else
		{
			var rpcErr = RpcId(1, MethodName.ServerSetReady, Multiplayer.GetUniqueId(), false);
			if (rpcErr != Error.Ok && StatusLabel != null)
				StatusLabel.Text = "> ERROR: UNREADY RPC FAILED";
		}

		UpdateReadyButtons();
		if (StatusLabel != null)
			StatusLabel.Text = "> STATUS: STANDBY [AWAITING INPUT]";
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerSetReady(int peerId, bool ready)
	{
		if (!Multiplayer.IsServer()) return;

		if (ready)
			_readyPeers.Add(peerId);
		else
			_readyPeers.Remove(peerId);

		_readyPlayerCount = _readyPeers.Count;
		Rpc(MethodName.SyncReadyCount, _readyPlayerCount);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncReadyCount(int count)
	{
		_readyPlayerCount = count;
		UpdateReadyCount();
	}

	private void UpdateReadyCount()
	{
		if (ReadyCountLabel != null)
		{
			int totalPlayers = _gameManager?.PlayerCount ?? 1;
			ReadyCountLabel.Text = $"> READY COUNT: {_readyPlayerCount}/{totalPlayers}";
		}
	}

	private void UpdateReadyButtons()
	{
		if (ReadyButton != null)
			ReadyButton.Disabled = _isReady;
		if (UnreadyButton != null)
			UnreadyButton.Disabled = !_isReady;
	}

	private void OnPreferencesPressed()
	{
		var prefScene = GD.Load<PackedScene>("uid://cqwq1gi0y8mph");
		if (prefScene != null)
		{
			var pref = prefScene.Instantiate();
			GetTree().Root.AddChild(pref);
			if (pref.HasMethod("popup_centered"))
				pref.Call("popup_centered");
		}
		else
		{
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("show_preferences"))
				prefManager.Call("show_preferences");
		}
	}

	private void OnObservePressed()
	{
		if (_gameManager != null && _gameManager.IsGameRunning())
		{
			if (Multiplayer.IsServer())
				_gameManager.BecomeObserver(Multiplayer.GetUniqueId());
			else
				_gameManager.Call("BecomeObserver", Multiplayer.GetUniqueId());
		}
		HideUI();
	}

	private void OnGameStarted()
	{
		_roundStarted = true;

		if (Multiplayer.IsServer())
		{
			Rpc(MethodName.ClientRoundStarted);
			if (_isReady)
				ServerRunPriorityAssignment();
			else
				ShowLateJoinPhase();
		}
		else
		{
			if (_isReady)
			{
				if (IsMultiplayerConnected())
					RpcId(1, MethodName.RequestPriorityAssignment, Multiplayer.GetUniqueId());
				else
					ShowLateJoinPhase();
			}
			else
				ShowLateJoinPhase();
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientRoundStarted()
	{
		_roundStarted = true;

		if (_isReady)
		{
			if (IsMultiplayerConnected())
				RpcId(1, MethodName.RequestPriorityAssignment, Multiplayer.GetUniqueId());
			else
				ShowLateJoinPhase();
		}
		else
			ShowLateJoinPhase();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestPriorityAssignment(int peerId)
	{
		if (!Multiplayer.IsServer()) return;
		AssignPeerByPriority(peerId);
	}

	private void ServerRunPriorityAssignment()
	{
		if (!Multiplayer.IsServer()) return;

		var rng = new System.Random();
		var shuffledPeers = _readyPeers.OrderBy(_ => rng.Next()).ToList();

		var high = new System.Collections.Generic.List<(int peerId, string role)>();
		var medium = new System.Collections.Generic.List<(int peerId, string role)>();
		var low = new System.Collections.Generic.List<(int peerId, string role)>();

		foreach (int peerId in shuffledPeers)
		{
			var charData = _gameManager?.GetPeerCharacterData(peerId);
			if (charData == null || !charData.ContainsKey("role_priorities"))
				continue;

			var rolePriorities = (Dictionary)charData["role_priorities"];
			bool placed = false;

			foreach (var roleKey in rolePriorities.Keys)
			{
				string role = roleKey.ToString();
				string prio = rolePriorities[roleKey].ToString();
				if (prio == "High") { high.Add((peerId, role)); placed = true; break; }
			}
			if (placed) continue;

			foreach (var roleKey in rolePriorities.Keys)
			{
				string role = roleKey.ToString();
				string prio = rolePriorities[roleKey].ToString();
				if (prio == "Medium") { medium.Add((peerId, role)); placed = true; break; }
			}
			if (placed) continue;

			foreach (var roleKey in rolePriorities.Keys)
			{
				string role = roleKey.ToString();
				string prio = rolePriorities[roleKey].ToString();
				if (prio == "Low") { low.Add((peerId, role)); break; }
			}
		}

		var assignedPeers = new System.Collections.Generic.HashSet<int>();

		foreach (var bucket in new[] { high, medium, low })
		{
			foreach (var (peerId, preferredRole) in bucket.OrderBy(_ => rng.Next()))
			{
				if (assignedPeers.Contains(peerId)) continue;

				var charData = _gameManager?.GetPeerCharacterData(peerId);
				Dictionary rolePriorities = charData != null && charData.ContainsKey("role_priorities")
					? (Dictionary)charData["role_priorities"]
					: new Dictionary();

				string assigned = _jobManager.AssignJobByPriority(peerId, rolePriorities);
				if (!string.IsNullOrEmpty(assigned))
				{
					assignedPeers.Add(peerId);
					SpawnPlayerAsJob(peerId, assigned);
					Rpc(MethodName.ClientNotifyAssigned, peerId, assigned);
				}
			}
		}

		foreach (int peerId in shuffledPeers)
		{
			if (assignedPeers.Contains(peerId)) continue;
			AssignPeerByPriority(peerId);
		}
	}

	private void AssignPeerByPriority(int peerId)
	{
		if (!Multiplayer.IsServer()) return;

		var charData = _gameManager?.GetPeerCharacterData(peerId);
		Dictionary rolePriorities = charData != null && charData.ContainsKey("role_priorities")
			? (Dictionary)charData["role_priorities"]
			: new Dictionary();

		string assigned = _jobManager.AssignJobByPriority(peerId, rolePriorities);
		if (!string.IsNullOrEmpty(assigned))
		{
			SpawnPlayerAsJob(peerId, assigned);
			Rpc(MethodName.ClientNotifyAssigned, peerId, assigned);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientNotifyAssigned(int peerId, string jobName)
	{
		if (Multiplayer.GetUniqueId() != peerId) return;

		if (StatusLabel != null)
			StatusLabel.Text = $"> ASSIGNED ROLE: {jobName.ToUpper()}";

		HideUI();
	}
	private void RefreshJobList()
	{
		if (_jobManager == null || JobTabs == null) return;

		var jobsByDept = _jobManager.GetJobsByDepartment();

		for (int i = JobTabs.GetChildCount() - 1; i >= 0; i--)
		{
			var child = JobTabs.GetChild(i);
			if (child is ScrollContainer)
				child.QueueFree();
		}

		var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
		string[] departments;
		if (prefManager != null)
		{
			var availableRoles = (Dictionary)prefManager.Get("available_roles");
			departments = availableRoles?.Keys.Select(k => k.ToString()).ToArray()
				?? new string[] { };
		}
		else
		{
			departments = new string[] { };
		}

		foreach (var dept in departments)
		{
			if (!jobsByDept.ContainsKey(dept)) continue;

			var jobs = (Array<Dictionary>)jobsByDept[dept];
			var scrollContainer = new ScrollContainer();
			scrollContainer.Name = dept;

			var vbox = new VBoxContainer();
			vbox.AddThemeConstantOverride("separation", 2);

			foreach (var jobData in jobs.OrderByDescending(j => (int)j["priority"]))
			{
				string jobName = (string)jobData["name"];
				int available = (int)jobData["available"];
				int filled = (int)jobData["filled"];
				int max = (int)jobData["max"];

				if (available <= 0) continue;

				var button = new Button();
				button.Text = $"[{filled}/{max}] {jobName.ToUpper()}";
				button.CustomMinimumSize = new Vector2(0, 28);
				button.Pressed += () => OnJobSelected(jobName);

				ApplyCctvButtonStyle(button);
				vbox.AddChild(button);
			}

			scrollContainer.AddChild(vbox);
			JobTabs.AddChild(scrollContainer);
		}
	}

	private void ApplyCctvButtonStyle(Button button)
	{
		var styleNormal = new StyleBoxFlat();
		styleNormal.BgColor = new Color(0.05f, 0.08f, 0.05f);
		styleNormal.BorderColor = new Color(0.0f, 0.8f, 0.0f);
		styleNormal.SetBorderWidthAll(1);
		styleNormal.SetCornerRadiusAll(0);
		button.AddThemeStyleboxOverride("normal", styleNormal);

		var styleHover = new StyleBoxFlat();
		styleHover.BgColor = new Color(0.1f, 0.2f, 0.1f);
		styleHover.BorderColor = new Color(0.0f, 1.0f, 0.0f);
		styleHover.SetBorderWidthAll(2);
		styleHover.SetCornerRadiusAll(0);
		button.AddThemeStyleboxOverride("hover", styleHover);

		var stylePressed = new StyleBoxFlat();
		stylePressed.BgColor = new Color(0.0f, 0.3f, 0.0f);
		stylePressed.BorderColor = new Color(0.0f, 1.0f, 0.0f);
		stylePressed.SetBorderWidthAll(2);
		stylePressed.SetCornerRadiusAll(0);
		button.AddThemeStyleboxOverride("pressed", stylePressed);

		button.AddThemeColorOverride("font_color", new Color(0.0f, 1.0f, 0.0f));
		button.AddThemeColorOverride("font_hover_color", new Color(0.2f, 1.0f, 0.2f));
		button.AddThemeColorOverride("font_pressed_color", new Color(1.0f, 1.0f, 1.0f));
	}

	private void OnJobSelected(string jobName)
	{
		_selectedJob = jobName;

		if (SelectedJobLabel != null)
			SelectedJobLabel.Text = $"> SELECTED ROLE: {jobName.ToUpper()}";
		if (JobDescriptionLabel != null)
			JobDescriptionLabel.Text = $"[color=#00ff00]> ROLE: {jobName}[/color]";
		if (JoinButton != null)
			JoinButton.Disabled = false;
	}

	private void OnJoinPressed()
	{
		if (string.IsNullOrEmpty(_selectedJob))
		{
			if (StatusLabel != null)
				StatusLabel.Text = "> ERROR: NO ROLE SELECTED";
			return;
		}
		JoinAsJob(_selectedJob);
	}

	private void JoinAsJob(string jobName)
	{
		var peerId = Multiplayer.GetUniqueId();

		if (Multiplayer.IsServer())
		{
			if (_jobManager.AssignJob(peerId, jobName))
			{
				SpawnPlayerAsJob(peerId, jobName);
				HideUI();
			}
			else
			{
				if (StatusLabel != null)
					StatusLabel.Text = $"> ERROR: {jobName.ToUpper()} NO LONGER AVAILABLE";
				RefreshJobList();
			}
		}
		else
		{
			if (JoinButton != null)
				JoinButton.Disabled = true;
			if (StatusLabel != null)
				StatusLabel.Text = $"> REQUESTING ROLE: {jobName.ToUpper()}...";

			if (!IsMultiplayerConnected())
			{
				if (StatusLabel != null)
					StatusLabel.Text = "> ERROR: NOT CONNECTED";
				if (JoinButton != null)
					JoinButton.Disabled = false;
				return;
			}

			var charData = new Dictionary();
			var prefManager = GetNodeOrNull<Node>("/root/PreferenceManager");
			if (prefManager != null && prefManager.HasMethod("get_character_data"))
				charData = (Dictionary)prefManager.Call("get_character_data");

			RpcId(1, MethodName.RequestSpawnAsJob, peerId, jobName, charData);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void RequestSpawnAsJob(int peerId, string jobName, Dictionary charData)
	{
		if (!Multiplayer.IsServer()) return;

		if (charData != null && charData.Count > 0)
			_gameManager?.SetPeerCharacterData(peerId, charData);

		if (_jobManager.AssignJob(peerId, jobName))
		{
			SpawnPlayerAsJob(peerId, jobName);
			RpcId(peerId, MethodName.ClientNotifyAssigned, peerId, jobName);
		}
		else
		{
			RpcId(peerId, MethodName.ClientJobNoLongerAvailable, jobName);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ClientJobNoLongerAvailable(string jobName)
	{
		if (StatusLabel != null)
			StatusLabel.Text = $"> ERROR: {jobName.ToUpper()} NO LONGER AVAILABLE";
		if (JoinButton != null)
			JoinButton.Disabled = false;
		_selectedJob = "";
		if (SelectedJobLabel != null)
			SelectedJobLabel.Text = "> SELECTED ROLE: NONE";
		RefreshJobList();
	}

	private void SpawnPlayerAsJob(int peerId, string jobName)
	{
		var spawnPoints = GetTree().GetNodesInGroup("SpawnPoint");
		Vector2 spawnPosition = Vector2.Zero;

		if (spawnPoints.Count > 0)
		{
			var spawnNode = spawnPoints[(int)(GD.Randi() % (uint)spawnPoints.Count)] as Node2D;
			if (spawnNode != null)
				spawnPosition = spawnNode.GlobalPosition;
		}

		if (_gameManager != null && _gameManager.HasMethod("SpawnPlayer"))
			_gameManager.Call("SpawnPlayer", peerId, spawnPosition, jobName);
	}

	public void HideUI()
	{
		Visible = false;
	}

	private void UpdateStatusForLateJoin()
	{
		if (StatusLabel != null)
			StatusLabel.Text = "> ROUND IN PROGRESS [SELECT ROLE TO JOIN]";
	}

	private void UpdateStatusForPreRound()
	{
		if (StatusLabel != null)
			StatusLabel.Text = "> AWAITING ROUND START [READY UP OR SELECT PREFERENCES]";
	}

	public override void _Process(double delta)
	{
		if (_roundStarted || _gameManager == null) return;

		if (TimerLabel != null)
		{
			var timeLeft = _gameManager.LobbyTimeLeft;
			var minutes = Mathf.FloorToInt(timeLeft / 60);
			var seconds = Mathf.FloorToInt(timeLeft % 60);
			TimerLabel.Text = $"> TIME UNTIL START: {minutes:D2}:{seconds:D2}";
		}

		if (ManifestLabel != null)
			ManifestLabel.Text = $"> CREW MANIFEST: {_gameManager.PlayerCount}/{_gameManager.MaxPlayers}";
	}

	public override void _ExitTree()
	{
		if (_bootTimer != null && IsInstanceValid(_bootTimer))
		{
			_bootTimer.Stop();
			_bootTimer.QueueFree();
		}

		if (_gameManager != null)
		{
			_gameManager.GameStarted -= OnGameStarted;
			_gameManager.PlayersUpdated -= UpdateReadyCount;
			_gameManager.RoundEnded -= OnRoundEnded;
		}

		if (_jobManager != null)
			_jobManager.JobAvailabilityChanged -= RefreshJobList;
	}
}
