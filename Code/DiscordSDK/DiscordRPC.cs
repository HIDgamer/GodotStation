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
	
	public void UpdatePresence(
		string state = null,
		string details = null,
		string largeImage = "godotstation",
		string largeText = "GodotStation",
		string smallImage = null,
		string smallText = null,
		int partySize = 0,
		int partyMax = 0,
		string partyId = null,
		string joinSecret = null,
		long? endTimestamp = null)
	{
		if (!_initialized) return;
		
		try
		{
			var presence = new DiscordRichPresence
			{
				state = state != null ? Marshal.StringToHGlobalAnsi(state) : IntPtr.Zero,
				details = details != null ? Marshal.StringToHGlobalAnsi(details) : IntPtr.Zero,
				startTimestamp = _startTime,
				endTimestamp = endTimestamp ?? 0,
				largeImageKey = largeImage != null ? Marshal.StringToHGlobalAnsi(largeImage) : IntPtr.Zero,
				largeImageText = largeText != null ? Marshal.StringToHGlobalAnsi(largeText) : IntPtr.Zero,
				smallImageKey = smallImage != null ? Marshal.StringToHGlobalAnsi(smallImage) : IntPtr.Zero,
				smallImageText = smallText != null ? Marshal.StringToHGlobalAnsi(smallText) : IntPtr.Zero,
				partyId = partyId != null ? Marshal.StringToHGlobalAnsi(partyId) : IntPtr.Zero,
				partySize = partySize,
				partyMax = partyMax,
				matchSecret = IntPtr.Zero,
				joinSecret = joinSecret != null ? Marshal.StringToHGlobalAnsi(joinSecret) : IntPtr.Zero,
				spectateSecret = IntPtr.Zero,
				instance = 0
			};
			
			Discord_UpdatePresence(ref presence);
			
			// Free allocated memory
			if (presence.state != IntPtr.Zero) Marshal.FreeHGlobal(presence.state);
			if (presence.details != IntPtr.Zero) Marshal.FreeHGlobal(presence.details);
			if (presence.largeImageKey != IntPtr.Zero) Marshal.FreeHGlobal(presence.largeImageKey);
			if (presence.largeImageText != IntPtr.Zero) Marshal.FreeHGlobal(presence.largeImageText);
			if (presence.smallImageKey != IntPtr.Zero) Marshal.FreeHGlobal(presence.smallImageKey);
			if (presence.smallImageText != IntPtr.Zero) Marshal.FreeHGlobal(presence.smallImageText);
			if (presence.partyId != IntPtr.Zero) Marshal.FreeHGlobal(presence.partyId);
			if (presence.joinSecret != IntPtr.Zero) Marshal.FreeHGlobal(presence.joinSecret);
			
			GD.Print($"[DiscordRPC] Updated: {state ?? "null"} | {details ?? "null"}");
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[DiscordRPC] Failed to update presence: {e.Message}");
		}
	}
	
	public void SetInLobby()
	{
		UpdatePresence(
			state: "In Lobby",
			details: "Browsing servers",
			largeImage: "godotstation",
			largeText: "GodotStation"
		);
	}
	
	public void SetInGame(string serverName, int currentPlayers, int maxPlayers, string mapName = null, string characterClass = null, int characterLevel = 0)
	{
		UpdatePresence(
			state: $"Playing Solo ({currentPlayers} of {maxPlayers})",
			details: serverName,
			largeImage: "godotstation",
			largeText: mapName ?? "GodotStation",
			smallImage: characterClass != null ? "godotstation512" : null,
			smallText: characterClass != null ? $"{characterClass} - Level {characterLevel}" : null
		);
	}
	
	public void SetHosting(string serverName, int currentPlayers, int maxPlayers)
	{
		UpdatePresence(
			state: $"Hosting: {currentPlayers}/{maxPlayers}",
			details: serverName,
			largeImage: "godotstation",
			largeText: "Hosting Server"
		);
	}
	
	public void SetWithParty(string state, string details, int partySize, int partyMax, string partyId, string joinSecret = null)
	{
		UpdatePresence(
			state: state,
			details: details,
			largeImage: "godotstation",
			largeText: "GodotStation",
			partySize: partySize,
			partyMax: partyMax,
			partyId: partyId,
			joinSecret: joinSecret
		);
	}
	
	public void SetCompetitive(string mode, string map, int partySize, int partyMax, string characterClass = null, int characterLevel = 0)
	{
		UpdatePresence(
			state: $"Playing Solo ({partySize} of {partyMax})",
			details: mode,
			largeImage: "godotstation",
			largeText: map,
			smallImage: characterClass != null ? "godotstation512" : null,
			smallText: characterClass != null ? $"{characterClass} - Level {characterLevel}" : null,
			partySize: partySize,
			partyMax: partyMax
		);
	}
	
	/// <summary>
	/// Clear Discord presence
	/// </summary>
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