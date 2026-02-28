using Godot;
using System.Collections.Generic;

public partial class Mob : CharacterBody2D
{
	[Export] public bool IsGhost;
	[Export] public bool DisableMovement;
	[Export] public bool Density { get; set; } = true;
	[Export] public bool CanBeDragCarried { get; set; } = true;

	private readonly List<IMobSystem> _systems = new();
	private GridSystem _gridSystem;
	private CollisionManager _collisionManager;
	private Vector2I _currentTile;
	private string _playerName = "";

	public override void _EnterTree()
	{
		if (int.TryParse(Name, out int peerId))
			SetMultiplayerAuthority(peerId);
		else
			SetMultiplayerAuthority((int)GetInstanceId());
	}

	public override void _Ready()
	{
		
		RegisterSystemsRecursive(this);
		ChildEnteredTree += OnChildEnteredTree;

		LoadCharacterData();
		
		if (IsMultiplayerAuthority())
		{
			if (!IsInGroup("Player"))
				AddToGroup("Player");

			var camera = GetNodeOrNull<Camera2D>("PlayerCameraSetup");
			if (camera == null)
			{
				camera = new Camera2D { Name = "PlayerCameraSetup", Zoom = new Vector2(3, 3) };
				AddChild(camera);
			}
			camera.Enabled = true;
			camera.MakeCurrent();
		}
		else
		{
			if (IsInGroup("Player"))
				RemoveFromGroup("Player");

			var camera = GetNodeOrNull<Camera2D>("PlayerCameraSetup");
			if (camera != null)
				camera.Enabled = false;
		}
		_gridSystem = FindGridSystem();
		_collisionManager = FindCollisionManager();
		
		if (_gridSystem != null)
		{
			_currentTile = _gridSystem.WorldToGrid(GlobalPosition);
			_gridSystem.RegisterEntity(this, _currentTile);
			_collisionManager?.EntityEnteredTile(this, _currentTile);
			GlobalPosition = _gridSystem.GridToWorld(_currentTile);
		}
		
		var wm = FindWorldManager();
		if (wm != null && _gridSystem != null)
		{
			var grid = wm.GetGrid();
			if (grid != null && grid.ContainsKey(_currentTile) && grid[_currentTile] == "wall")
			{
				grid[_currentTile] = "floor";
				wm.UpdateTileRpc(_currentTile, "floor");
			}
		}
	}

	private void RegisterSystemsRecursive(Node root)
	{
		foreach (Node child in root.GetChildren())
		{
			if (child is IMobSystem system)
			{
				if (!_systems.Contains(system))
				{
					_systems.Add(system);
					system.Init(this);
				}
			}
			if (child.GetChildCount() > 0)
				RegisterSystemsRecursive(child);
		}
	}

	private void OnChildEnteredTree(Node child)
	{
		RegisterSystemsRecursive(child);
	}
	
	private void LoadCharacterData()
	{
		var prefManager = GetNodeOrNull("/root/PreferenceManager");
		var gameManager = GetNodeOrNull("/root/GameManager");
		
		if (prefManager != null && int.TryParse(Name, out int peerId))
		{
			if (gameManager != null)
			{
				var charData = (Godot.Collections.Dictionary)gameManager.Call("GetPeerCharacterData", peerId);
				if (charData != null && charData.Count > 0)
				{
					SetPlayerName((string)charData.GetValueOrDefault("name", "Player " + Name));
					ApplyAppearance(charData);
					return;
				}
			}
			
			var charData2 = (Godot.Collections.Dictionary)prefManager.Call("get_peer_character_data", peerId);
			if (charData2 != null && charData2.Count > 0)
			{
				SetPlayerName((string)charData2.GetValueOrDefault("name", "Player " + Name));
				ApplyAppearance(charData2);
				return;
			}
		}
		
		SetPlayerName("Player " + Name);
	}
	
	public void SetPlayerName(string playerName)
	{
		_playerName = playerName;
		
		var nameLabel = GetNodeOrNull<Label>("NameLabel");
		nameLabel?.QueueFree();
	}

	public override void _Process(double delta)
	{
		foreach (var system in _systems)
			system.Process(delta);
		
		if (_gridSystem != null)
		{
			var newTile = _gridSystem.WorldToGrid(GlobalPosition);
			if (newTile != _currentTile)
			{
				ExitedTile(_currentTile);
				_currentTile = newTile;
				EnteredTile(_currentTile);
			}
		}
	}

	private void EnteredTile(Vector2I tile)
	{
		_gridSystem?.RegisterEntity(this, tile);
		_collisionManager?.EntityEnteredTile(this, tile);
	}

	private void ExitedTile(Vector2I tile)
	{
		_gridSystem?.UnregisterEntity(this, tile);
		_collisionManager?.EntityExitedTile(this, tile);
	}

	public void ShowChatBubble(string message, string mode = "IC", bool addToChat = true)
	{
		if (addToChat)
		{
			var communications = GetNodeOrNull("/root/Communications");
			if (communications == null && GetTree().CurrentScene?.Name == "Communications")
				communications = GetTree().CurrentScene;
			communications?.Call("AddChatMessage", message, mode, _playerName);
		}

		Rpc(MethodName.ShowChatBubbleRpc, message, mode);
	}
	public void ShowPrivateThought(string message)
	{
		if (IsMultiplayerAuthority())
		{
			_show_chat_bubble_local(message, "THOUGHT");
		}
	}
	public void ShowPrivateMessageTo(int targetPeerId, string message)
	{
		RpcId(targetPeerId, nameof(ShowPrivateMessageRpc), targetPeerId, message);
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = false, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ShowPrivateMessageRpc(int targetPeerId, string message)
	{
		if (GetMultiplayerAuthority() == targetPeerId)
		{
			_show_chat_bubble_local(message, "IC");
		}
	}

	[Rpc(MultiplayerApi.RpcMode.AnyPeer, CallLocal = true, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
	private void ShowChatBubbleRpc(string message, string mode = "IC")
	{
		_show_chat_bubble_local(message, mode);
	}

	private void _show_chat_bubble_local(string message, string mode = "IC")
	{
		if (string.IsNullOrWhiteSpace(message))
			return;

		Node2D existingBubble = null;
		foreach (Node child in GetChildren())
		{
			if (child.Name.ToString().Contains("ChatBubble") && child is Node2D)
			{
				existingBubble = (Node2D)child;
				break;
			}
		}

		if (existingBubble != null)
		{
			existingBubble.Call("update_message", message, mode);
		}
		else
		{
			var bubbleScene = GD.Load<PackedScene>("res://Scenes/game/interface/ChatBubble.tscn");
			if (bubbleScene != null)
			{
				var bubble = bubbleScene.Instantiate<Node2D>();
				bubble.Position = new Vector2(0, -25);
				AddChild(bubble);
				bubble.Call("set_message", message, mode);
			}
		}
	}

	public override void _Input(InputEvent @event)
	{
		if (IsMultiplayerAuthority() && @event.IsActionPressed("ghost"))
		{
			IsGhost = !IsGhost;
			GetViewport().SetInputAsHandled();
		}
	}


	public override void _ExitTree()
	{
		if (_gridSystem != null)
			_gridSystem.UnregisterEntity(this, _currentTile);
			
		foreach (var system in _systems)
			system.Cleanup();
		_systems.Clear();
	}

	public void ApplyAppearance(Godot.Collections.Dictionary playerData)
	{
		var spriteSystem = GetNodeOrNull<SpriteSystem>("SpriteSystem");
		if (spriteSystem != null && playerData != null && playerData.Count > 0)
		{
			spriteSystem.ApplyAppearanceWithData(playerData);
		}
	}

	public void ApplyCharacterData(Godot.Collections.Dictionary charData)
	{
		if (charData != null && charData.Count > 0)
		{
			var charName = charData.ContainsKey("name") ? charData["name"].ToString() : "Player " + Name;
			SetPlayerName(charName);
			ApplyAppearance(charData);
		}

		// Re-evaluate authority in case the node was renamed after _EnterTree.
		// This is the critical fix for reconnecting players.
		RefreshAuthority();
	}

	public void RefreshAuthority()
	{
		// Re-derive authority from the current node name (may differ after a rename).
		if (int.TryParse(Name, out int peerId))
			SetMultiplayerAuthority(peerId);

		var isAuthority = IsMultiplayerAuthority();
		if (isAuthority)
		{
			if (!IsInGroup("Player"))
				AddToGroup("Player");
		}
		else if (IsInGroup("Player"))
		{
			RemoveFromGroup("Player");
		}

		// Find or create the camera.
		var camera = GetNodeOrNull<Camera2D>("PlayerCameraSetup");
		if (isAuthority && camera == null)
		{
			camera = new Camera2D { Name = "PlayerCameraSetup", Zoom = new Vector2(3, 3) };
			AddChild(camera);
		}

		if (camera != null)
		{
			camera.Enabled = isAuthority;
			if (isAuthority)
				camera.MakeCurrent();
		}

		// Re-enable processing for all IMobSystems on the local (authority) mob.
		if (isAuthority)
		{
			foreach (var system in _systems)
			{
				if (system is Node sysNode)
					sysNode.ProcessMode = ProcessModeEnum.Inherit;
			}
		}
	}
	
	public string GetPlayerName()
	{
		return _playerName;
	}
	
	private WorldManager FindWorldManager()
	{
		Node current = this;
		while (current != null)
		{
			var wm = current.GetNodeOrNull<WorldManager>("WorldManager");
			if (wm != null)
				return wm;
			current = current.GetParent();
		}
		return null;
	}
	
	private GridSystem FindGridSystem()
	{
		var wm = FindWorldManager();
		if (wm != null)
		{
			var grid = wm.GetNodeOrNull<GridSystem>("GridSystem");
			if (grid != null)
				return grid;
		}
		
		Node current = this;
		while (current != null)
		{
			var grid = current.GetNodeOrNull<GridSystem>("GridSystem");
			if (grid != null)
				return grid;
			current = current.GetParent();
		}
		return null;
	}
	
	private CollisionManager FindCollisionManager()
	{
		var wm = FindWorldManager();
		if (wm != null)
		{
			var collision = wm.GetNodeOrNull<CollisionManager>("CollisionManager");
			if (collision != null)
				return collision;
		}
		
		Node current = this;
		while (current != null)
		{
			var collision = current.GetNodeOrNull<CollisionManager>("CollisionManager");
			if (collision != null)
				return collision;
			current = current.GetParent();
		}
		return null;
	}
}
