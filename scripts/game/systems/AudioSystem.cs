using Godot;

public partial class AudioSystem : Node
{
	private static AudioSystem _instance;
	
	public static AudioSystem Instance => _instance;
	
	[Export] public AudioStreamPlayer PunchSound;
	[Export] public AudioStreamPlayer PunchMissSound;
	[Export] public AudioStreamPlayer DisarmSound;
	[Export] public AudioStreamPlayer GrabSound;
	[Export] public AudioStreamPlayer HelpSound;
	[Export] public AudioStreamPlayer StunSound;
	
	public override void _Ready()
	{
		_instance = this;
	}
	
	public static void PlayPunchSound()
	{
		_instance?.PunchSound?.Play();
	}
	
	public static void PlayPunchMissSound()
	{
		_instance?.PunchMissSound?.Play();
	}
	
	public static void PlayDisarmSound()
	{
		_instance?.DisarmSound?.Play();
	}
	
	public static void PlayGrabSound()
	{
		_instance?.GrabSound?.Play();
	}
	
	public static void PlayHelpSound()
	{
		_instance?.HelpSound?.Play();
	}
	
	public static void PlayStunSound()
	{
		_instance?.StunSound?.Play();
	}
}
