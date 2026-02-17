using Godot;
using System.Collections.Generic;

public partial class EntitySpawner : Node2D
{
	[Signal] public delegate void SpawnMobEventHandler(Vector2 position, Godot.Collections.Dictionary characterData);
	[Signal] public delegate void RandomizePreferencesEventHandler();
	
	private GameManager _gameManager;
	private OptionButton _mobTypeDropdown;
	private Button _spawnButton;
	private Button _randomizeButton;
	private Button _closeButton;
	private Label _statusLabel;
	
	private List<string> _mobTypes = new List<string>
	{
		"Human"
	};
	
	public override void _Ready()
	{
		_gameManager = GetNodeOrNull<GameManager>("/root/GameManager");
		
		_mobTypeDropdown = GetNode<OptionButton>("EntitySpawnerWindow/VBox/MobRow/MobTypeDropdown");
		_spawnButton = GetNode<Button>("EntitySpawnerWindow/VBox/SpawnButton");
		_randomizeButton = GetNode<Button>("EntitySpawnerWindow/VBox/RandomizeButton");
		_statusLabel = GetNode<Label>("EntitySpawnerWindow/VBox/StatusLabel");
		
		foreach (var mobType in _mobTypes)
		{
			_mobTypeDropdown.AddItem(mobType);
		}
		
		_spawnButton.Pressed += OnSpawnButtonPressed;
		_randomizeButton.Pressed += OnRandomizeButtonPressed;
		
		SpawnMob += OnSpawnMobRequested;
		
		_closeButton = GetNodeOrNull<Button>("EntitySpawnerWindow/VBox/CloseButton");
		if (_closeButton != null)
		{
			_closeButton.Pressed += OnCloseButtonPressed;
		}
		
		Visible = false;
	}
	
	private void OnSpawnButtonPressed()
	{
		var mobType = _mobTypeDropdown.Text;
		var characterData = GenerateRandomCharacterData(mobType);
		
		EmitSignal(SignalName.SpawnMob, Vector2.Zero, characterData);
		_statusLabel.Text = $"Status: Spawned {mobType}";
	}
	private void OnRandomizeButtonPressed()
	{
		EmitSignal(SignalName.RandomizePreferences);
		_statusLabel.Text = "Status: Preferences randomized";
	}
	
	private void OnSpawnMobRequested(Vector2 position, Godot.Collections.Dictionary characterData)
	{
		if (_gameManager != null)
		{
			if (Multiplayer.IsServer())
			{
				var world = GetTree().GetFirstNodeInGroup("World");
				if (world != null)
				{
					Vector2 spawnPos = position == Vector2.Zero ? new Vector2(2 * 32, 2 * 32) : position;
					int mobId = Multiplayer.GetUniqueId();
					string jobName = "Civilian";
					_gameManager.SpawnPlayer(mobId, spawnPos, jobName);
					_statusLabel.Text = $"Status: Spawned {characterData["mob_type"]} at {spawnPos}";
				}
				else
				{
					_statusLabel.Text = "Status: Error - World not found";
				}
			}
			else
			{
				_statusLabel.Text = "Status: Error - Can only spawn on server";
			}
		}
		else
		{
			_statusLabel.Text = "Status: Error - GameManager not found";
		}
	}
	
	private void OnCloseButtonPressed()
	{
		Visible = false;
		_statusLabel.Text = "Status: Window closed";
	}
	
	public void ShowSpawner()
	{
		Visible = true;
		_statusLabel.Text = "Status: Ready";
	}
	
	private Godot.Collections.Dictionary GenerateRandomCharacterData(string mobType)
	{
		var characterData = new Godot.Collections.Dictionary
		{
			["name"] = GenerateRandomName(),
			["age"] = GD.RandRange(18, 50),
			["religion"] = GenerateRandomReligion(),
			["clothing"] = GetDefaultClothingForType(mobType),
			["underwear"] = "1",
			["hair_style"] = GenerateRandomHairStyle(),
			["facial_hair_style"] = GenerateRandomFacialHairStyle(),
			["underwear_style"] = "1",
			["undershirt_style"] = "1",
			["hair_base_color"] = GenerateRandomColor(),
			["hair_gradient_color"] = GenerateRandomColor(),
			["eye_color"] = GenerateRandomColor(),
			["race"] = GenerateRandomRace(),
			["gender"] = GenerateRandomGender(),
			["traits"] = new Godot.Collections.Array<string>(),
			["role_priorities"] = new Godot.Collections.Dictionary(),
			["background"] = GenerateRandomBackground(),
			["randomize_name"] = false,
			["randomize_appearance"] = false,
			["origin"] = GenerateRandomOrigin(),
			["relations"] = "",
			["pref_squad"] = "",
			["assigned_roles"] = new Godot.Collections.Dictionary(),
			["mob_type"] = mobType,
			["is_debug_mob"] = true
		};
		
		return characterData;
	}
	
	private string GenerateRandomName()
	{
		var firstNames = new string[] { "John", "Jane", "Alex", "Chris", "Sam", "Taylor", "Jordan", "Morgan", "Casey", "Riley" };
		var lastNames = new string[] { "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez" };
		
		return $"{firstNames[GD.RandRange(0, firstNames.Length - 1)]} {lastNames[GD.RandRange(0, lastNames.Length - 1)]}";
	}
	
	private string GenerateRandomReligion()
	{
		var religions = new string[] { "Atheist", "Christian", "Muslim", "Hindu", "Buddhist", "Jewish", "Agnostic", "Scientologist" };
		return religions[GD.RandRange(0, religions.Length - 1)];
	}
	
	private string GenerateRandomHairStyle()
	{
		var styles = new string[] { "(1)", "(2)", "(3)", "(4)", "(5)", "(6)", "(7)", "(8)", "(9)", "(10)" };
		return styles[GD.RandRange(0, styles.Length - 1)];
	}
	
	private string GenerateRandomFacialHairStyle()
	{
		var styles = new string[] { "_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8", "_9", "_10" };
		return styles[GD.RandRange(0, styles.Length - 1)];
	}
	
	private string GenerateRandomColor()
	{
		var r = GD.RandRange(0, 255);
		var g = GD.RandRange(0, 255);
		var b = GD.RandRange(0, 255);
		return $"#{r:X2}{g:X2}{b:X2}";
	}
	
	private string GenerateRandomRace()
	{
		var races = new string[] { "Western", "Eastern", "African", "Asian", "Hispanic", "Mixed" };
		return races[GD.RandRange(0, races.Length - 1)];
	}
	
	private string GenerateRandomGender()
	{
		var genders = new string[] { "Male", "Female", "Non-Binary" };
		return genders[GD.RandRange(0, genders.Length - 1)];
	}
	
	private string GenerateRandomBackground()
	{
		var backgrounds = new string[] 
		{ 
			"Former civilian contractor", 
			"Ex-military personnel", 
			"Scientific researcher", 
			"Corporate employee",
			"Colonial settler",
			"Space explorer",
			"Medical professional",
			"Engineer by trade"
		};
		return backgrounds[GD.RandRange(0, backgrounds.Length - 1)];
	}
	
	private string GenerateRandomOrigin()
	{
		var origins = new string[] 
		{ 
			"Earth", 
			"Mars Colony", 
			"Luna Base", 
			"Titan Station",
			"Europa Outpost",
			"Venus Orbital",
			"Deep Space Born"
		};
		return origins[GD.RandRange(0, origins.Length - 1)];
	}
	
	private string GetDefaultClothingForType(string mobType)
	{
		switch (mobType)
		{
			case "Marine": return "Marine Uniform";
			case "Scientist": return "Lab Coat";
			case "Engineer": return "Engineering Suit";
			case "Medic": return "Medical Scrubs";
			case "Security": return "Security Uniform";
			case "Synthetic": return "Synthetic Frame";
			default: return "Standard Uniform";
		}
	}
}
