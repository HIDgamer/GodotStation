using Godot;

public partial class StateController : Node, IMobSystem
{
	private Mob _owner;
	private MobStateSystem _states;

	public void Init(Mob mob)
	{
		_owner = mob;
		_states = mob.GetNodeOrNull<MobStateSystem>("MobStateSystem");
		SetProcess(true);
	}

	public override void _Ready()
	{
		SetProcess(true);
	}

	public override void _Input(InputEvent e)
	{
		if (!_owner.IsMultiplayerAuthority()) return;

		if (Input.IsActionJustPressed("go_prone"))
			ToggleProne();
	}

	private void ToggleProne()
	{
		if (_states == null) return;

		var current = _states.GetState();

		if (current == MobState.Prone)
		{
			if (Multiplayer.IsServer())
				_states.SetState(MobState.Standing);
			else
				RpcId(1, nameof(ServerToggleProne), _owner.GetPath());
		}
		else if (current == MobState.Standing)
		{
			if (Multiplayer.IsServer())
				_states.SetState(MobState.Prone);
			else
				RpcId(1, nameof(ServerToggleProne), _owner.GetPath());
		}
	}

	private void ToggleRest()
	{
		if (_states == null) return;

		var next = _states.GetState() == MobState.Sleeping
			? MobState.Standing
			: MobState.Sleeping;

		if (Multiplayer.IsServer())
			_states.SetState(next);
		else
			RpcId(1, nameof(ServerToggleRest), _owner.GetPath());
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerToggleProne(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		GetNodeOrNull<Mob>(mobPath)?
			.GetNodeOrNull<StateController>("StateController")?
			.ToggleProne();
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerToggleRest(NodePath mobPath)
	{
		if (!Multiplayer.IsServer()) return;
		GetNodeOrNull<Mob>(mobPath)?
			.GetNodeOrNull<StateController>("StateController")?
			.ToggleRest();
	}

	public void Process(double delta) { }
	public override void _Process(double delta) { }
	public void Cleanup() { }
}
