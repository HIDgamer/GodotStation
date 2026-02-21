using Godot;
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

public partial class DiscordRPC : Node
{
	[Export] public string ApplicationId = "1470420296040189995";
	[Export] public bool Enabled = true;

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

	[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
	private struct DiscordRichPresence
	{
		public IntPtr state;
		public IntPtr details;
		public long startTimestamp;
		public long endTimestamp;
		public IntPtr largeImageKey;
		public IntPtr largeImageText;
		public IntPtr smallImageKey;
		public IntPtr smallImageText;
		public IntPtr partyId;
		public int partySize;
		public int partyMax;
		public IntPtr matchSecret;
		public IntPtr joinSecret;
		public IntPtr spectateSecret;
		public byte instance;
	}

	private static bool _resolverInstalled = false;
	private static string _resolvedLibraryPath = "";
	private static IntPtr _nativeLibraryHandle = IntPtr.Zero;

	private bool _initialized = false;
	private long _startTime;

	public override void _Ready()
	{
		if (OS.HasFeature("dedicated_server") ||
			string.Equals(DisplayServer.GetName(), "headless", StringComparison.OrdinalIgnoreCase))
		{
			return;
		}

		if (!Enabled)
		{
			GD.Print("[DiscordRPC] Disabled in settings");
			return;
		}

		EnsureNativeResolver();
		Initialize();
	}

	private static void EnsureNativeResolver()
	{
		if (_resolverInstalled)
			return;

		try
		{
			NativeLibrary.SetDllImportResolver(typeof(DiscordRPC).Assembly, ResolveDiscordRpc);
		}
		catch (InvalidOperationException)
		{
		}

		_resolverInstalled = true;
	}

	private static IntPtr ResolveDiscordRpc(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
	{
		if (!string.Equals(libraryName, "discord-rpc", StringComparison.OrdinalIgnoreCase))
			return IntPtr.Zero;

		if (_nativeLibraryHandle != IntPtr.Zero)
			return _nativeLibraryHandle;

		foreach (var candidate in GetDiscordLibraryCandidates())
		{
			if (!File.Exists(candidate))
				continue;
			if (NativeLibrary.TryLoad(candidate, out var handle))
			{
				_nativeLibraryHandle = handle;
				_resolvedLibraryPath = candidate;
				return handle;
			}
		}

		if (NativeLibrary.TryLoad(libraryName, assembly, searchPath, out var fallbackHandle))
		{
			_nativeLibraryHandle = fallbackHandle;
			_resolvedLibraryPath = libraryName;
			return fallbackHandle;
		}

		return IntPtr.Zero;
	}

	private static IEnumerable<string> GetDiscordLibraryCandidates()
	{
		var fileName = OS.GetName() switch
		{
			"Windows" => "discord-rpc.dll",
			"Linux" => "libdiscord-rpc.so",
			"macOS" => "libdiscord-rpc.dylib",
			_ => "discord-rpc"
		};

		var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
		foreach (var dir in GetNativeSearchDirectories())
		{
			if (string.IsNullOrWhiteSpace(dir))
				continue;
			var fullPath = Path.GetFullPath(Path.Combine(dir, fileName));
			if (seen.Add(fullPath))
				yield return fullPath;
		}
	}

	private static IEnumerable<string> GetNativeSearchDirectories()
	{
		var assemblyDirectory = Path.GetDirectoryName(typeof(DiscordRPC).Assembly.Location) ?? "";

		yield return AppContext.BaseDirectory;
		yield return Path.Combine(AppContext.BaseDirectory, "Code", "DiscordSDK");
		yield return System.Environment.CurrentDirectory;
		yield return Path.Combine(System.Environment.CurrentDirectory, "Code", "DiscordSDK");
		yield return assemblyDirectory;
		yield return Path.Combine(assemblyDirectory, "Code", "DiscordSDK");
		yield return ProjectSettings.GlobalizePath("res://");
		yield return ProjectSettings.GlobalizePath("res://Code/DiscordSDK");
		yield return ProjectSettings.GlobalizePath("res://bin");
		yield return ProjectSettings.GlobalizePath("res://.godot/mono/temp/bin/Debug");
		yield return ProjectSettings.GlobalizePath("res://.godot/mono/temp/bin/Release");
	}

	private static void TryPreloadNativeLibrary()
	{
		if (_nativeLibraryHandle != IntPtr.Zero)
			return;

		foreach (var candidate in GetDiscordLibraryCandidates())
		{
			if (!File.Exists(candidate))
				continue;
			if (NativeLibrary.TryLoad(candidate, out var handle))
			{
				_nativeLibraryHandle = handle;
				_resolvedLibraryPath = candidate;
				return;
			}
		}
	}

	private static void PrintLibraryHints()
	{
		GD.PrintErr("[DiscordRPC] discord-rpc library not found");
		GD.PrintErr("[DiscordRPC] expected file names:");
		GD.PrintErr("[DiscordRPC]   discord-rpc.dll (Windows)");
		GD.PrintErr("[DiscordRPC]   libdiscord-rpc.so (Linux)");
		GD.PrintErr("[DiscordRPC]   libdiscord-rpc.dylib (macOS)");
		GD.PrintErr("[DiscordRPC] searched paths:");
		foreach (var candidate in GetDiscordLibraryCandidates())
		{
			GD.PrintErr("[DiscordRPC]   " + candidate);
		}
	}

	private void Initialize()
	{
		try
		{
			TryPreloadNativeLibrary();

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

			GD.Print("[DiscordRPC] Initialized successfully");
			GD.Print("[DiscordRPC] Application ID: " + ApplicationId);
			if (!string.IsNullOrWhiteSpace(_resolvedLibraryPath))
				GD.Print("[DiscordRPC] Native library: " + _resolvedLibraryPath);

			SetInLobby();
		}
		catch (DllNotFoundException)
		{
			PrintLibraryHints();
		}
		catch (BadImageFormatException e)
		{
			GD.PrintErr("[DiscordRPC] Native library architecture mismatch");
			GD.PrintErr($"[DiscordRPC] {e.Message}");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[DiscordRPC] Failed to initialize: {e.Message}");
		}
	}

	public override void _Process(double delta)
	{
		if (_initialized)
			Discord_RunCallbacks();
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
		if (!_initialized)
			return;

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
		catch (Exception e)
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

	public void SetInGame(string serverName, int currentPlayers, int maxPlayers, string mapName, string characterClass, int characterLevel = 0)
	{
		var mode = string.IsNullOrWhiteSpace(characterClass) ? "In Match" : characterClass;
		var server = string.IsNullOrWhiteSpace(serverName) ? "Unknown Server" : serverName;
		UpdatePresence(
			state: $"{currentPlayers}/{maxPlayers} players",
			details: $"{server} - {mode}",
			largeImage: "godotstation",
			largeText: string.IsNullOrWhiteSpace(mapName) ? "Unknown Map" : mapName,
			smallImage: !string.IsNullOrWhiteSpace(characterClass) ? "godotstation512" : null,
			smallText: !string.IsNullOrWhiteSpace(characterClass) ? characterClass : null
		);
	}

	public void SetInGame(string serverName, int currentPlayers, int maxPlayers, string mapName)
	{
		SetInGame(serverName, currentPlayers, maxPlayers, mapName, null, 0);
	}

	public void SetInGame(string serverName, int currentPlayers, int maxPlayers)
	{
		SetInGame(serverName, currentPlayers, maxPlayers, null, null, 0);
	}

	public void SetHosting(string serverName, int currentPlayers, int maxPlayers)
	{
		var server = string.IsNullOrWhiteSpace(serverName) ? "Unknown Server" : serverName;
		UpdatePresence(
			state: $"Hosting: {currentPlayers}/{maxPlayers}",
			details: server,
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
			state: $"{partySize}/{partyMax} players",
			details: mode,
			largeImage: "godotstation",
			largeText: map,
			smallImage: characterClass != null ? "godotstation512" : null,
			smallText: characterClass != null ? $"{characterClass} - Level {characterLevel}" : null,
			partySize: partySize,
			partyMax: partyMax
		);
	}

	public void ClearPresence()
	{
		if (!_initialized)
			return;

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
