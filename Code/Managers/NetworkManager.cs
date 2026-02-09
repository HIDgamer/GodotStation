using Godot;
using System.Collections.Generic;

public partial class NetworkManager : Node
{
	[Export] public float SyncInterval = 0.05f;
	[Export] public float InterpolationSpeed = 15.0f;

	private class PlayerState
	{
		public Vector2 Position;
		public float Rotation;
		public int Direction;
		public string AnimState = "idle";
		public bool Peeking;
		public Vector2 MouseTarget;
	}

	private Dictionary<int, PlayerState> _states = new();
	private Dictionary<int, float> _lastSync = new();

	public override void _EnterTree()
	{
		Multiplayer.PeerConnected += OnPeerJoined;
		Multiplayer.PeerDisconnected += OnPeerLeft;
	}

	public override void _Process(double delta)
	{
		foreach (var kvp in _states)
		{
			if (kvp.Key == Multiplayer.GetUniqueId())
				continue;
			
			var player = GetPlayer(kvp.Key);
			if (player is Node2D node)
			{
				if (ShouldSkipInterpolation(player))
					continue;
				node.GlobalPosition = node.GlobalPosition.Lerp(kvp.Value.Position, InterpolationSpeed * (float)delta);
				node.Rotation = Mathf.LerpAngle(node.Rotation, kvp.Value.Rotation, InterpolationSpeed * (float)delta);
			}
		}
	}

	private bool ShouldSkipInterpolation(Node player)
	{
		if (player is Mob mob)
		{
			var interaction = mob.GetNodeOrNull<PlayerInteractionSystem>("PlayerInteractionSystem");
			if (interaction?.GetPulledBy() != null)
				return true;
		}
		return false;
	}

	private void OnPeerJoined(long id)
	{
		var peerId = (int)id;
		_states.Remove(peerId);
		_lastSync.Remove(peerId);
		
		// Update Discord presence when a player joins
		var discord = GetNode<DiscordRPC>("/root/DiscordRPC");
		var gameManager = GetNode<GameManager>("/root/GameManager");
		
		if (gameManager.IsHost)
		{
			discord.SetHosting(
				gameManager.ServerName,
				gameManager.PlayerCount,
				gameManager.MaxPlayers
			);
		}
		else
		{
			discord.SetInGame(
				gameManager.ServerName,
				gameManager.PlayerCount,
				gameManager.MaxPlayers
			);
		}
	}

	private void OnPeerLeft(long id)
	{
		_states.Remove((int)id);
		_lastSync.Remove((int)id);
	}

	public void SyncTransform(int peerId, Vector2 position, float rotation)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		_lastSync[peerId] = 0.0f;
		Rpc(MethodName.OnTransformSync, peerId, position, rotation);
	}

	public void SyncDirection(int peerId, int direction)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		Rpc(MethodName.OnDirectionSync, peerId, direction);
	}

	public void SyncState(int peerId, string state)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		Rpc(MethodName.OnStateSync, peerId, state);
	}

	public void SyncPeeking(int peerId, bool peeking)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		Rpc(MethodName.OnPeekingSync, peerId, peeking);
	}

	public void SyncMouseTarget(int peerId, Vector2 target)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		Rpc(MethodName.OnMouseSync, peerId, target);
	}

	public void SyncHeadFrame(int peerId, int frame)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;
		
		Rpc(MethodName.OnHeadSync, peerId, frame);
	}

	public void SyncGrabbedPosition(int peerId, Vector2 position)
	{
		if (!Multiplayer.IsServer() && peerId != Multiplayer.GetUniqueId())
			return;

		Rpc(MethodName.OnGrabbedPositionSync, peerId, position);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void OnTransformSync(int peerId, Vector2 position, float rotation)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetOrCreateState(peerId).Position = position;
		GetOrCreateState(peerId).Rotation = rotation;
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void OnDirectionSync(int peerId, int direction)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetOrCreateState(peerId).Direction = direction;
		GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetDirection", direction);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void OnStateSync(int peerId, string state)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetOrCreateState(peerId).AnimState = state;
		GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetState", state);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void OnPeekingSync(int peerId, bool peeking)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetOrCreateState(peerId).Peeking = peeking;
		GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetPeeking", peeking);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void OnMouseSync(int peerId, Vector2 target)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetOrCreateState(peerId).MouseTarget = target;
		GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetMouseTarget", target);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Unreliable)]
	private void OnHeadSync(int peerId, int frame)
	{
		if (peerId == Multiplayer.GetUniqueId())
			return;
		
		GetPlayer(peerId)?.GetNodeOrNull("SpriteSystem")?.Call("SetHeadFrame", frame);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void OnGrabbedPositionSync(int peerId, Vector2 position)
	{
		var player = GetPlayer(peerId);
		GetOrCreateState(peerId).Position = position;
		if (player is Node2D node)
		{
			node.GlobalPosition = position;
		}
	}

	private PlayerState GetOrCreateState(int peerId)
	{
		if (!_states.ContainsKey(peerId))
		{
			_states[peerId] = new PlayerState
			{
				Position = Vector2.Zero,
				Rotation = 0.0f,
				Direction = 0,
				AnimState = "idle",
				Peeking = false,
				MouseTarget = Vector2.Zero
			};
		}
		return _states[peerId];
	}

	private Node GetPlayer(int peerId)
	{
		var world = GetTree().GetFirstNodeInGroup("World");
		return world?.GetNodeOrNull(peerId.ToString());
	}

	public void Cleanup()
	{
		_states.Clear();
		_lastSync.Clear();
	}
}
