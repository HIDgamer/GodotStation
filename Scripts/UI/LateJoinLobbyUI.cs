using Godot;
using GodotStation.Game.Jobs;
using System.Collections.Generic;
using System.Linq;

namespace GodotStation.UI;

// Ready-up + job picker, ported from the old prototype (its own original
// code) - drastically simplified against the current architecture:
//  - GameManager doesn't exist, and GameRoot.ServerStartRound doesn't check
//    readiness at all - Ready/Unready has nothing left to gate, so it's
//    local-only display state now rather than networked (ReadyCountLabel
//    stays as static scene text - there's no cross-peer count to show).
//  - No priority-bucket job assignment (old role_priorities came from a
//    character-creation system that doesn't exist yet, Phase 6) - the job
//    panel is a flat picker calling JobManager.AssignJob directly.
//  - GameRoot already auto-spawns a connecting peer with a fallback job
//    (JobManager.AssignFallback, see GameRoot.OnPeerConnected) the instant
//    they connect during a running round - before this panel could ever
//    show and intercept that. So "join as job" here is a reassignment
//    (updates JobManager's record for next respawn) rather than a spawn
//    trigger - spawning stays entirely GameRoot's job. True "pick a role
//    before you spawn" late-join needs GameRoot's auto-spawn deferred,
//    which is out of scope for this pass.
//  - Button wiring stays in the .tscn's own [connection] blocks (as
//    restored) rather than re-wired in code, to avoid double-firing -
//    method names below match those connections exactly.
//  - Boot sequence and CCTV button styling are kept close to verbatim -
//    pure cosmetic, no dead-system dependency.
public partial class LateJoinLobbyUI : Control
{
    [Export] public Control? PreRoundPanel;
    [Export] public Control? LateJoinPanel;
    [Export] public Label? StatusLabel;
    [Export] public Label? CharacterNameLabel;
    [Export] public Button? ReadyButton;
    [Export] public Button? UnreadyButton;
    [Export] public Button? PreferencesButton;
    [Export] public Button? ObserveButton;
    [Export] public Label? ReadyCountLabel;
    [Export] public Label? TimerLabel;
    [Export] public Label? ManifestLabel;

    [Export] public TabContainer? JobTabs;
    [Export] public Button? JoinButton;
    [Export] public Label? SelectedJobLabel;
    [Export] public RichTextLabel? JobDescriptionLabel;

    private const string PreferencesPopupUid = "uid://cqwq1gi0y8mph";

    private JobManager? _jobManager;
    private string _selectedJob = "";
    private bool _isReady;
    private Timer? _bootTimer;
    private int _bootPhase;

    private static readonly string[] BootMessages =
    {
        ">", "> .", "> ..", "> ...",
        "> INITIALIZING TERMINAL...", "> CONNECTING TO STATION DATABASE...",
        "> LOADING CREW MANIFEST...", "> TERMINAL READY",
    };

    public override void _Ready()
    {
        _jobManager = GetNodeOrNull<JobManager>("/root/JobManager");
        if (_jobManager != null) _jobManager.JobAvailabilityChanged += RefreshJobList;

        if (CharacterNameLabel != null) CharacterNameLabel.Text = "> OPERATOR: MARINE";
        PlayBootSequence();
    }

    private void PlayBootSequence()
    {
        _bootTimer = new Timer { WaitTime = 0.15f };
        _bootTimer.Timeout += OnBootTimerTimeout;
        AddChild(_bootTimer);
        _bootTimer.Start();
        if (StatusLabel != null) StatusLabel.Text = ">";
    }

    private void OnBootTimerTimeout()
    {
        if (_bootPhase < BootMessages.Length)
        {
            if (StatusLabel != null) StatusLabel.Text = BootMessages[_bootPhase];
            _bootPhase++;
            return;
        }

        _bootTimer?.Stop();
        UpdateManifestLabel();
        ShowPreRoundPhase();
    }

    private void ShowPreRoundPhase()
    {
        if (PreRoundPanel != null) PreRoundPanel.Visible = true;
        if (LateJoinPanel != null) LateJoinPanel.Visible = false;
        UpdateReadyButtons();
        if (StatusLabel != null) StatusLabel.Text = "> AWAITING ROUND START [READY UP OR SELECT ROLE]";
    }

    // Public - Communications.gd's show_late_join_ui() is the intended
    // caller once a real "defer spawn until role pick" flow exists (see
    // header). Not wired to anything automatically yet.
    public void ShowLateJoinPhase()
    {
        if (PreRoundPanel != null) PreRoundPanel.Visible = false;
        if (LateJoinPanel != null) LateJoinPanel.Visible = true;
        RefreshJobList();
        if (StatusLabel != null) StatusLabel.Text = "> ROUND IN PROGRESS [SELECT A ROLE]";
    }

    private void UpdateManifestLabel()
    {
        if (ManifestLabel == null) return;
        var count = Multiplayer.HasMultiplayerPeer() ? Multiplayer.GetPeers().Length + 1 : 1;
        ManifestLabel.Text = $"> CREW MANIFEST: {count}";
    }

    // [connection]-bound - see LateJoinLobbyUI.tscn.
    private void OnReadyPressed()
    {
        _isReady = true;
        UpdateReadyButtons();
        if (StatusLabel != null) StatusLabel.Text = "> STATUS: READY [AWAITING ROUND START]";
    }

    private void OnUnreadyPressed()
    {
        _isReady = false;
        UpdateReadyButtons();
        if (StatusLabel != null) StatusLabel.Text = "> STATUS: STANDBY [AWAITING INPUT]";
    }

    private void UpdateReadyButtons()
    {
        if (ReadyButton != null) ReadyButton.Disabled = _isReady;
        if (UnreadyButton != null) UnreadyButton.Disabled = !_isReady;
    }

    private void OnPreferencesPressed()
    {
        if (!ResourceLoader.Exists(PreferencesPopupUid))
        {
            if (StatusLabel != null) StatusLabel.Text = "> CHARACTER SETUP NOT YET AVAILABLE";
            return;
        }

        var scene = GD.Load<PackedScene>(PreferencesPopupUid);
        var pref = scene.Instantiate();
        GetTree().Root.AddChild(pref);
        if (pref.HasMethod("popup_centered")) pref.Call("popup_centered");
    }

    private void OnObservePressed() => Visible = false;

    private void RefreshJobList()
    {
        if (_jobManager == null || JobTabs == null) return;

        for (var i = JobTabs.GetChildCount() - 1; i >= 0; i--)
        {
            JobTabs.GetChild(i).QueueFree();
        }

        var byDepartment = new Dictionary<string, List<(string Name, JobSlot Slot)>>();
        foreach (var (name, slot) in _jobManager.Jobs)
        {
            if (!byDepartment.TryGetValue(slot.Department, out var list))
            {
                list = new List<(string, JobSlot)>();
                byDepartment[slot.Department] = list;
            }
            list.Add((name, slot));
        }

        foreach (var (department, jobs) in byDepartment)
        {
            var scrollContainer = new ScrollContainer { Name = department };
            var vbox = new VBoxContainer();
            vbox.AddThemeConstantOverride("separation", 2);

            foreach (var (jobName, slot) in jobs.OrderByDescending(j => j.Slot.Priority))
            {
                if (slot.IsFull) continue;

                var button = new Button
                {
                    Text = $"[{slot.FilledSlots}/{slot.MaxSlots}] {jobName.ToUpperInvariant()}",
                    CustomMinimumSize = new Vector2(0, 28),
                };
                button.Pressed += () => OnJobSelected(jobName);
                ApplyCctvButtonStyle(button);
                vbox.AddChild(button);
            }

            scrollContainer.AddChild(vbox);
            JobTabs.AddChild(scrollContainer);
        }
    }

    private static void ApplyCctvButtonStyle(Button button)
    {
        var styleNormal = new StyleBoxFlat { BgColor = new Color(0.05f, 0.08f, 0.05f), BorderColor = new Color(0f, 0.8f, 0f) };
        styleNormal.SetBorderWidthAll(1);
        button.AddThemeStyleboxOverride("normal", styleNormal);

        var styleHover = new StyleBoxFlat { BgColor = new Color(0.1f, 0.2f, 0.1f), BorderColor = new Color(0f, 1f, 0f) };
        styleHover.SetBorderWidthAll(2);
        button.AddThemeStyleboxOverride("hover", styleHover);

        var stylePressed = new StyleBoxFlat { BgColor = new Color(0f, 0.3f, 0f), BorderColor = new Color(0f, 1f, 0f) };
        stylePressed.SetBorderWidthAll(2);
        button.AddThemeStyleboxOverride("pressed", stylePressed);

        button.AddThemeColorOverride("font_color", new Color(0f, 1f, 0f));
        button.AddThemeColorOverride("font_hover_color", new Color(0.2f, 1f, 0.2f));
        button.AddThemeColorOverride("font_pressed_color", Colors.White);
    }

    private void OnJobSelected(string jobName)
    {
        _selectedJob = jobName;
        if (SelectedJobLabel != null) SelectedJobLabel.Text = $"> SELECTED ROLE: {jobName.ToUpperInvariant()}";
        if (JobDescriptionLabel != null) JobDescriptionLabel.Text = $"[color=#00ff00]> ROLE: {jobName}[/color]";
        if (JoinButton != null) JoinButton.Disabled = false;
    }

    // [connection]-bound - see LateJoinLobbyUI.tscn.
    private void OnJoinPressed()
    {
        if (string.IsNullOrEmpty(_selectedJob))
        {
            if (StatusLabel != null) StatusLabel.Text = "> ERROR: NO ROLE SELECTED";
            return;
        }

        var peerId = Multiplayer.GetUniqueId();
        if (Multiplayer.IsServer()) DoAssignJob(peerId, _selectedJob);
        else RpcId(1, MethodName.RequestAssignJob, peerId, _selectedJob);
    }

    [Rpc(MultiplayerApi.RpcMode.AnyPeer)]
    private void RequestAssignJob(int peerId, string jobName)
    {
        if (!Multiplayer.IsServer() || Multiplayer.GetRemoteSenderId() != peerId) return;
        DoAssignJob(peerId, jobName);
    }

    private void DoAssignJob(int peerId, string jobName)
    {
        if (_jobManager == null) return;

        if (_jobManager.AssignJob(peerId, jobName))
        {
            RpcId(peerId, MethodName.ClientJobAssigned, jobName);
        }
        else
        {
            RpcId(peerId, MethodName.ClientJobUnavailable, jobName);
        }
    }

    [Rpc(MultiplayerApi.RpcMode.Authority)]
    private void ClientJobAssigned(string jobName)
    {
        if (StatusLabel != null) StatusLabel.Text = $"> ROLE SET: {jobName.ToUpperInvariant()} (takes effect next respawn)";
        Visible = false;
    }

    [Rpc(MultiplayerApi.RpcMode.Authority)]
    private void ClientJobUnavailable(string jobName)
    {
        if (StatusLabel != null) StatusLabel.Text = $"> ERROR: {jobName.ToUpperInvariant()} NO LONGER AVAILABLE";
        if (JoinButton != null) JoinButton.Disabled = true;
        _selectedJob = "";
        if (SelectedJobLabel != null) SelectedJobLabel.Text = "> SELECTED ROLE: NONE";
        RefreshJobList();
    }

    public override void _ExitTree()
    {
        if (_bootTimer != null && IsInstanceValid(_bootTimer))
        {
            _bootTimer.Stop();
            _bootTimer.QueueFree();
        }
        if (_jobManager != null) _jobManager.JobAvailabilityChanged -= RefreshJobList;
    }
}
