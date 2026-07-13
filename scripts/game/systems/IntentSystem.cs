using Godot;

public enum Intent { Help, Disarm, Grab, Harm }

public partial class IntentSystem : Node, IMobSystem
{
	private Mob _owner;
	private Intent _intent = Intent.Help;
	private bool _isPeeking = false;
	
	[Signal] public delegate void IntentChangedEventHandler(int newIntent);
	[Signal] public delegate void PeekingChangedEventHandler(bool isPeeking);
	
	public void Init(Mob mob) => _owner = mob;
	
	public override void _Input(InputEvent @event)
	{
		if (!_owner.IsMultiplayerAuthority()) return;
		
		Intent? newIntent = null;
		if (@event.IsActionPressed("intent_help")) newIntent = Intent.Help;
		else if (@event.IsActionPressed("intent_disarm")) newIntent = Intent.Disarm;
		else if (@event.IsActionPressed("intent_grab")) newIntent = Intent.Grab;
		else if (@event.IsActionPressed("intent_harm")) newIntent = Intent.Harm;
		
		if (newIntent.HasValue)
		{
			SetIntent(newIntent.Value);
			GetViewport().SetInputAsHandled();
		}
	}
	
	public override void _UnhandledInput(InputEvent @event)
	{
		if (!_owner.IsMultiplayerAuthority()) return;
		
		if (@event.IsActionPressed("peek"))
		{
			TogglePeeking();
			GetViewport().SetInputAsHandled();
		}
	}
	
	public void SetIntent(Intent intent)
	{
		if (_intent == intent) return;

		ApplyIntent(intent, Multiplayer.IsServer());

		if (!Multiplayer.IsServer())
			RpcId(1, nameof(ServerSetIntentRpc), (int)intent);
	}

	private void ApplyIntent(Intent intent, bool broadcast)
	{
		var interactionSystem = _owner.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
		interactionSystem?.OnIntentChanged(intent);

		_intent = intent;
		EmitSignal(SignalName.IntentChanged, (int)intent);

		if (broadcast)
			Rpc(MethodName.SyncIntent, (int)intent);
	}
	
	public void TogglePeeking()
	{
		SetPeeking(!_isPeeking);
	}
	
	public void SetPeeking(bool peeking)
	{
		if (_isPeeking != peeking)
		{
			_isPeeking = peeking;
			EmitSignal(SignalName.PeekingChanged, peeking);
			
			if (Multiplayer.IsServer())
				Rpc(MethodName.SyncPeeking, peeking);
		}
	}
	
	public Intent GetIntent() => _intent;
	public bool IsPeeking() => _isPeeking;
	public void Process(double delta) { }
	public void Cleanup() { }
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncIntent(int intent)
	{
		ApplyIntent((Intent)intent, false);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ServerSetIntentRpc(int intent)
	{
		if (!Multiplayer.IsServer()) return;
		ApplyIntent((Intent)intent, true);
	}
	
	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void SyncPeeking(bool peeking)
	{
		_isPeeking = peeking;
		EmitSignal(SignalName.PeekingChanged, peeking);
	}
}
