using Godot;

namespace GodotStation.Core.Net;

// Local (server-relayed, all-peers) chat, with a mode tag (IC/OOC/LOOC/ME/
// System) for the restored Communications UI's mode-colored formatting -
// still one flat relay, not per-channel routing (radio/say-range are future
// work), the mode is just carried through as a string the receiver decides
// how to render.
public partial class ChatManager : Node
{
	private const int MaxMessageLength = 500;

	[Signal] public delegate void MessageReceivedEventHandler(string speakerName, string text, string mode);

	public void SendLocalMessage(string text, string mode = "IC")
	{
		text = text.Trim();
		if (text.Length == 0) return;
		if (text.Length > MaxMessageLength) text = text.Substring(0, MaxMessageLength);

		if (Multiplayer.IsServer())
		{
			Relay(Multiplayer.GetUniqueId(), text, mode);
		}
		else
		{
			RpcId(1, nameof(ReceiveFromClient), text, mode);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer)]
	private void ReceiveFromClient(string text, string mode)
	{
		if (!Multiplayer.IsServer()) return;
		Relay(Multiplayer.GetRemoteSenderId(), text, mode);
	}

	private void Relay(long senderId, string text, string mode)
	{
		Rpc(nameof(BroadcastMessage), $"Player {senderId}", text, mode);
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = true)]
	private void BroadcastMessage(string speakerName, string text, string mode)
	{
		EmitSignal(SignalName.MessageReceived, speakerName, text, mode);
	}

	// Private feedback (examine text, failed-action messages, ...) visible only
	// to the one peer it's for - server-only caller. Not routed through
	// BroadcastMessage since that always fans out to everyone.
	public void SendSystemMessage(long toPeerId, string text)
	{
		if (!Multiplayer.IsServer()) return;

		if (toPeerId == Multiplayer.GetUniqueId())
		{
			EmitSignal(SignalName.MessageReceived, "System", text, "System");
		}
		else
		{
			RpcId(toPeerId, nameof(ReceiveSystemMessage), text);
		}
	}

	[Rpc(MultiplayerApi.RpcMode.Authority, CallLocal = false)]
	private void ReceiveSystemMessage(string text)
	{
		EmitSignal(SignalName.MessageReceived, "System", text, "System");
	}
}
