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
		if (_world == null || !IsInstanceValid(_world))
			_world = GetTree().GetFirstNodeInGroup("World");
		
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
		
		var world = GetTree().GetFirstNodeInGroup("World");
		var gridSystem = world?.GetNodeOrNull<GridSystem>("GridSystem");
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
		if (!string.IsNullOrEmpty(item?.ScenePath))
			return item.ScenePath;

		if (item is ClothingItem)
		{
			return item.ItemName switch
			{
				"Marine_CM_Uniform" => "uid://bafal7piiq62r",
				"Medical_Scrubs" => "uid://cmekjlejs76dx",
				"MA_Light_Armor" => "uid://dokjyi8xbqq3f",
				"MA_Medium_Armor" => "uid://vcq5pgy5hx6q",
				"MA_Heavy_Armor" => "uid://bivuy3j7hqmiy",
				"Marine_Boots" => "uid://cm766a6sb2g85",
				"Combat_Boots" => "uid://3u2w8gvxgm1l",
				"Marine_Gloves" => "uid://eafyncq222qn",
				"Armored_Gloves" => "uid://bcijgf8bgu24c",
				_ => null
			};
		}
		return null;
	}
}
