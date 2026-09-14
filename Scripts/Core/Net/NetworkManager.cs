using Godot;
using GodotStation.Core.Diagnostics;

namespace GodotStation.Core.Net;

// Thin wrapper around Godot's high-level multiplayer API (ENetMultiplayerPeer).
// Owns only connection lifecycle - it does not spawn players itself. Callers
// (the lobby UI, GameRoot) subscribe to PeerConnected/PeerDisconnected and
// decide what a connecting peer means (join the lobby roster vs. spawn a mob
// mid-round), so this class stays reusable if a second connection surface
// (e.g. a dedicated-server admin channel) is ever needed.
public partial class NetworkManager : Node
{
	public const int DefaultPort = 8910;
	private const int MaxPlayers = 32;

	[Signal] public delegate void PeerConnectedEventHandler(long id);
	[Signal] public delegate void PeerDisconnectedEventHandler(long id);
	[Signal] public delegate void ServerCreatedEventHandler();
	[Signal] public delegate void ConnectedToServerEventHandler();
	[Signal] public delegate void ConnectionFailedEventHandler();

	public bool IsServer { get; private set; }

	private RoundLogger? _log;

	public override void _Ready()
	{
		_log = GetNodeOrNull<RoundLogger>("/root/RoundLogger");

		Multiplayer.PeerConnected += id => { _log?.Log("NETWORK", $"Peer connected: {id}"); EmitSignal(SignalName.PeerConnected, id); };
		Multiplayer.PeerDisconnected += id => { _log?.Log("NETWORK", $"Peer disconnected: {id}"); EmitSignal(SignalName.PeerDisconnected, id); };
		Multiplayer.ConnectedToServer += () => { _log?.Log("NETWORK", "Connected to server."); EmitSignal(SignalName.ConnectedToServer); };
		Multiplayer.ConnectionFailed += () => { _log?.Log("NETWORK", "Connection failed."); EmitSignal(SignalName.ConnectionFailed); };
	}

	// No-default overloads - GDScript calling a C# method with default
	// parameter values omitted can fail to resolve the bind on some Godot
	// Mono versions ("Nonexistent function"), so the zero-arg entry points
	// GDScript actually calls are explicit rather than relying on optional args.
	public Error Host() => Host(DefaultPort);

	public Error Host(int port)
	{
		var peer = new ENetMultiplayerPeer();
		var err = peer.CreateServer(port, MaxPlayers);
		if (err != Error.Ok)
		{
			GD.PrintErr($"[NetworkManager] CreateServer failed: {err}");
			return err;
		}

		GD.Print($"[NetworkManager] Listening on port {port}.");
		Multiplayer.MultiplayerPeer = peer;
		IsServer = true;
		EmitSignal(SignalName.ServerCreated);
		return Error.Ok;
	}

	public Error Join(string address) => Join(address, DefaultPort);

	public Error Join(string address, int port)
	{
		var peer = new ENetMultiplayerPeer();
		var err = peer.CreateClient(address, port);
		if (err != Error.Ok)
		{
			GD.PrintErr($"[NetworkManager] CreateClient failed: {err}");
			return err;
		}

		GD.Print($"[NetworkManager] Connecting to {address}:{port}...");
		Multiplayer.MultiplayerPeer = peer;
		IsServer = false;
		return Error.Ok;
	}

	public void Disconnect()
	{
		Multiplayer.MultiplayerPeer?.Close();
		Multiplayer.MultiplayerPeer = null;
	}
}
