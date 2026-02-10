using Godot;
using System;
using System.Runtime.InteropServices;

public partial class DiscordRPC : Node
{
	[Export] public string ApplicationId = "1470420296040189995";
	[Export] public bool Enabled = true;
	
	// Discord RPC native functions
	[DllImport("discord-rpc", CallingConvention = CallingConvention.Cdecl)]
	private static extern void Discord_Initialize(string applicationId, ref DiscordEventHandlers handlers, bool autoRegister, string optionalSteamId);
	
	[DllImport("discord-rpc", CallingConvention = CallingConvention.Cdecl)]
	private static extern void Discord_Shutdown();
	
	[DllImport("discord-rpc", CallingConvention = CallingConvention.Cdecl)]
	private static extern void Discord_UpdatePresence(ref DiscordRichPresence presence);
	
	[DllImport("discord-rpc", CallingConvention = CallingConvention.Cdecl)]
	private static extern void Discord_ClearPresence();
	
	[DllImport("discord-rpc", CallingConvention = CallingConvention.Cdecl)]
	private static extern void Discord_RunCallbacks();
	
	// Discord event handlers structure
	[StructLayout(LayoutKind.Sequential)]
	private struct DiscordEventHandlers
	{
		public IntPtr ready;
		public IntPtr disconnected;
		public IntPtr errored;
		public IntPtr joinGame;
		public IntPtr spectateGame;
		public IntPtr joinRequest;
	}
	
	// Discord Rich Presence structure
	[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
	private struct DiscordRichPresence
	{
		public IntPtr state;           // "3/8 players"
		public IntPtr details;         // "Playing on Awesome Server"
		public long startTimestamp;    // Unix timestamp
		public long endTimestamp;      // Unix timestamp (0 = no end time)
		public IntPtr largeImageKey;   // Asset key from developer portal
		public IntPtr largeImageText;  // Hover text for large image
		public IntPtr smallImageKey;   // Asset key for small image
		public IntPtr smallImageText;  // Hover text for small image
		public IntPtr partyId;         // Unique party ID
		public int partySize;          // Current party size
		public int partyMax;           // Max party size
		public IntPtr matchSecret;     // Secret for matching
		public IntPtr joinSecret;      // Secret for joining
		public IntPtr spectateSecret;  // Secret for spectating
		public byte instance;          // Instance flag
	}
	
	private bool _initialized = false;
	private long _startTime;
	
	public override void _Ready()
	{
		if (!Enabled)
		{
			GD.Print("[DiscordRPC] Disabled in settings");
			return;
		}
		
		Initialize();
	}
	
	private void Initialize()
	{
		try
		{
			var handlers = new DiscordEventHandlers
			{
				ready = IntPtr.Zero,
				disconnected = IntPtr.Zero,
				errored = IntPtr.Zero,
				joinGame = IntPtr.Zero,
				spectateGame = IntPtr.Zero,
				joinRequest = IntPtr.Zero
			};
			
			Discord_Initialize(ApplicationId, ref handlers, true, null);
			_initialized = true;
			_startTime = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
			
			GD.Print("[DiscordRPC] ✓ Initialized successfully");
			GD.Print("[DiscordRPC] Application ID: " + ApplicationId);
			
			// Set initial presence
			SetInLobby();
		}
		catch (DllNotFoundException)
		{
			GD.PrintErr("[DiscordRPC] discord-rpc library not found!");
			GD.PrintErr("[DiscordRPC] Windows: Place discord-rpc.dll in project root");
			GD.PrintErr("[DiscordRPC] Linux: Place libdiscord-rpc.so in project root");
			GD.PrintErr("[DiscordRPC] Download from: https://github.com/discord/discord-rpc/releases");
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[DiscordRPC] Failed to initialize: {e.Message}");
		}
	}
	
	public override void _Process(double delta)
	{
		if (_initialized)
		{
			// Discord requires callbacks to be run regularly
			Discord_RunCallbacks();
		}
	}
	
	public void UpdatePresence(string state, string details, string largeImage = "logo", string largeText = "GodotStation")
	{
		if (!_initialized) return;
		
		try
		{
			var presence = new DiscordRichPresence
			{
				state = Marshal.StringToHGlobalAnsi(state ?? ""),
				details = Marshal.StringToHGlobalAnsi(details ?? ""),
				startTimestamp = _startTime,
				endTimestamp = 0,
				largeImageKey = Marshal.StringToHGlobalAnsi(largeImage ?? ""),
				largeImageText = Marshal.StringToHGlobalAnsi(largeText ?? ""),
				smallImageKey = IntPtr.Zero,
				smallImageText = IntPtr.Zero,
				partyId = IntPtr.Zero,
				partySize = 0,
				partyMax = 0,
				matchSecret = IntPtr.Zero,
				joinSecret = IntPtr.Zero,
				spectateSecret = IntPtr.Zero,
				instance = 0
			};
			
			Discord_UpdatePresence(ref presence);
			
			// Free allocated memory
			Marshal.FreeHGlobal(presence.state);
			Marshal.FreeHGlobal(presence.details);
			Marshal.FreeHGlobal(presence.largeImageKey);
			Marshal.FreeHGlobal(presence.largeImageText);
			
			GD.Print($"[DiscordRPC] Updated: {state} | {details}");
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[DiscordRPC] Failed to update presence: {e.Message}");
		}
	}
	
	/// <summary>
	/// Set presence to "In Lobby" state
	/// </summary>
	public void SetInLobby()
	{
		UpdatePresence("In Lobby", "Browsing servers", "logo", "GodotStation");
	}
	
	public void SetInGame(string serverName, int currentPlayers, int maxPlayers)
	{
		var state = $"{currentPlayers}/{maxPlayers} players";
		var details = $"Playing: {serverName}";
		UpdatePresence(state, details, "ingame", "In Game");
	}
	public void SetHosting(string serverName, int currentPlayers, int maxPlayers)
	{
		var state = $"Hosting: {currentPlayers}/{maxPlayers}";
		var details = serverName;
		UpdatePresence(state, details, "host", "Hosting Server");
	}
	
	public void SetWithParty(string state, string details, int partySize, int partyMax, string partyId)
	{
		if (!_initialized) return;
		
		try
		{
			var presence = new DiscordRichPresence
			{
				state = Marshal.StringToHGlobalAnsi(state ?? ""),
				details = Marshal.StringToHGlobalAnsi(details ?? ""),
				startTimestamp = _startTime,
				endTimestamp = 0,
				largeImageKey = Marshal.StringToHGlobalAnsi("logo"),
				largeImageText = Marshal.StringToHGlobalAnsi("GodotStation"),
				smallImageKey = IntPtr.Zero,
				smallImageText = IntPtr.Zero,
				partyId = Marshal.StringToHGlobalAnsi(partyId ?? ""),
				partySize = partySize,
				partyMax = partyMax,
				matchSecret = IntPtr.Zero,
				joinSecret = IntPtr.Zero,
				spectateSecret = IntPtr.Zero,
				instance = 0
			};
			
			Discord_UpdatePresence(ref presence);
			
			// Free allocated memory
			Marshal.FreeHGlobal(presence.state);
			Marshal.FreeHGlobal(presence.details);
			Marshal.FreeHGlobal(presence.largeImageKey);
			Marshal.FreeHGlobal(presence.largeImageText);
			Marshal.FreeHGlobal(presence.partyId);
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[DiscordRPC] Failed to update presence with party: {e.Message}");
		}
	}
	public void ClearPresence()
	{
		if (!_initialized) return;
		
		Discord_ClearPresence();
		GD.Print("[DiscordRPC] Presence cleared");
	}
	
	public override void _ExitTree()
	{
		if (_initialized)
		{
			Discord_Shutdown();
			_initialized = false;
			GD.Print("[DiscordRPC] Shutdown complete");
		}
	}
}
