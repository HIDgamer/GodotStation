using Godot;
using System.Collections.Generic;

public partial class ItemPoolManager : Node
{
	private Dictionary<string, Queue<WorldItem>> _pools = new();
	private Dictionary<string, PackedScene> _sceneCache = new();
	private Node _world;
	
	public override void _Ready()
	{
		_world = GetTree().GetFirstNodeInGroup("World");
	}
	
	public WorldItem Get(Item item, Vector2 position)
	{
		string scenePath = GetScenePath(item);
		if (scenePath == null) return null;
		
		if (!_pools.ContainsKey(scenePath))
			_pools[scenePath] = new Queue<WorldItem>();
		
		WorldItem worldItem;
		
		if (_pools[scenePath].Count > 0)
		{
			worldItem = _pools[scenePath].Dequeue();
			worldItem.Visible = true;
			worldItem.ProcessMode = ProcessModeEnum.Inherit;
			worldItem.ResetForPool();
			worldItem.InitAtPosition(position);
		}
		else
		{
			if (!_sceneCache.ContainsKey(scenePath))
				_sceneCache[scenePath] = GD.Load<PackedScene>(scenePath);
			
			worldItem = _sceneCache[scenePath]?.Instantiate<WorldItem>();
			if (worldItem == null) return null;
			
			worldItem.PrepareSpawn(position);
			
			if (_world != null)
				_world.AddChild(worldItem, true);
			
			worldItem.InitAtPosition(position);
		}
		
		return worldItem;
	}
	
	public void Return(WorldItem item)
	{
		if (!IsInstanceValid(item)) return;
		
		string scenePath = item.SceneFilePath;
		if (string.IsNullOrEmpty(scenePath)) return;
		
		if (!_pools.ContainsKey(scenePath))
			_pools[scenePath] = new Queue<WorldItem>();
		
		var gridSystem = item.GetNodeOrNull<GridSystem>("/root/World/GridSystem");
		if (gridSystem != null)
		{
			var tile = gridSystem.WorldToGrid(item.GlobalPosition);
			gridSystem.UnregisterEntity(item, tile);
		}
		
		item.Visible = false;
		item.ProcessMode = ProcessModeEnum.Disabled;
		item.GlobalPosition = Vector2.Zero;
		_pools[scenePath].Enqueue(item);
	}
	
	private string GetScenePath(Item item)
	{
		if (item is ClothingItem)
		{
			return item.ItemName switch
			{
				"Marine_CM_Uniform" => "uid://c123456789abcdef", // Marine_CM_Uniform.tscn
				"Medical_Scrubs" => "uid://d123456789abcdef", // Medical_Scrubs.tscn
				"MA_Light_Armor" => "uid://e123456789abcdef", // MA_Light_Armor.tscn
				"MA_Medium_Armor" => "uid://f123456789abcdef", // MA_Medium_Armor.tscn
				"MA_Heavy_Armor" => "uid://g123456789abcdef", // MA_Heavy_Armor.tscn
				"Marine_Boots" => "uid://h123456789abcdef", // Marine_Boots.tscn
				"Combat_Boots" => "uid://i123456789abcdef", // Combat_Boots.tscn
				"Marine_Gloves" => "uid://j123456789abcdef", // Marine_Gloves.tscn
				"Armored_Gloves" => "uid://k123456789abcdef", // Armored_Gloves.tscn
				_ => null
			};
		}
		return $"uid://l123456789abcdef"; // Generic item scene
	}
}
