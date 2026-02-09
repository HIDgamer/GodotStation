using Godot;
using Godot.Collections;
using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using System.Diagnostics;
using SystemHttpClient = System.Net.Http.HttpClient;
using SystemFileAccess = System.IO.FileAccess;
using SystemFileStream = System.IO.FileStream;


public partial class AutoUpdater : Node
{
	// Update sources
	[Export] public string UpdateServerUrl = "http://150.136.90.194:3000/updates";
	[Export] public string GitHubRepo = "HIDgamer/GodotStation";
	[Export] public bool CheckOnStartup = true;
	[Export] public bool AutoDownload = true;
	
	[Export] public string CurrentVersion = "0.9.0";
	
	// Signals
	[Signal] public delegate void UpdateAvailableEventHandler(string newVersion, string currentVersion);
	[Signal] public delegate void UpdateDownloadProgressEventHandler(float progress);
	[Signal] public delegate void UpdateReadyEventHandler();
	[Signal] public delegate void UpdateErrorEventHandler(string error);
	[Signal] public delegate void NoUpdateAvailableEventHandler();
	
	private System.Net.Http.HttpClient _httpClient;
	private string _updatePath;
	private string _executablePath;
	
	public override void _Ready()
	{
		var client = new SystemHttpClient();
		_updatePath = OS.GetUserDataDir() + "/updates";
		_executablePath = OS.GetExecutablePath();
		
		// Create updates directory
		if (!DirAccess.DirExistsAbsolute(_updatePath))
		{
			DirAccess.MakeDirRecursiveAbsolute(_updatePath);
		}
		
		GD.Print($"[AutoUpdater] Current version: {CurrentVersion}");
		GD.Print($"[AutoUpdater] Update path: {_updatePath}");
		
		if (CheckOnStartup)
		{
			CallDeferred(MethodName.CheckForUpdates);
		}
	}
	public async void CheckForUpdates()
	{
		GD.Print("[AutoUpdater] Checking for updates...");
		
		try
		{
			// Try Oracle Cloud first (faster)
			var manifest = await GetUpdateManifest($"{UpdateServerUrl}/version-manifest.json");
			
			if (manifest == null)
			{
				// Fallback to GitHub releases
				manifest = await GetGitHubLatestRelease();
			}
			
			if (manifest == null)
			{
				EmitSignal(SignalName.UpdateError, "Could not check for updates");
				return;
			}
			
			var latestVersion = manifest.ContainsKey("version") ? manifest["version"].ToString() : "";
			
			if (string.IsNullOrEmpty(latestVersion))
			{
				EmitSignal(SignalName.UpdateError, "Invalid version manifest");
				return;
			}
			
			GD.Print($"[AutoUpdater] Latest version: {latestVersion}");
			
			if (IsNewerVersion(latestVersion, CurrentVersion))
			{
				GD.Print($"[AutoUpdater] Update available! {CurrentVersion} -> {latestVersion}");
				EmitSignal(SignalName.UpdateAvailable, latestVersion, CurrentVersion);
				
				if (AutoDownload)
				{
					DownloadUpdate(manifest);
				}
			}
			else
			{
				GD.Print("[AutoUpdater] You're up to date!");
				EmitSignal(SignalName.NoUpdateAvailable);
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[AutoUpdater] Error checking for updates: {e.Message}");
			EmitSignal(SignalName.UpdateError, e.Message);
		}
	}
	
	public async void DownloadUpdate(Dictionary manifest)
	{
		try
		{
			var platforms = manifest["platforms"].AsGodotDictionary();
			var platform = GetCurrentPlatform();
			
			if (!platforms.ContainsKey(platform))
			{
				EmitSignal(SignalName.UpdateError, $"No update available for {platform}");
				return;
			}
			
			var platformData = platforms[platform].AsGodotDictionary();
			var downloadUrl = platformData["url"].ToString();
			var fileSize = Convert.ToInt64(platformData["size"]);
			
			GD.Print($"[AutoUpdater] Downloading update from: {downloadUrl}");
			GD.Print($"[AutoUpdater] Size: {fileSize / 1024 / 1024} MB");
			
			var updateFile = $"{_updatePath}/update.zip";
			
			// Download with progress
			await DownloadFileWithProgress(downloadUrl, updateFile);
			
			GD.Print("[AutoUpdater] Download complete!");
			GD.Print("[AutoUpdater] Extracting update...");
			
			// Extract update
			ExtractUpdate(updateFile);
			
			GD.Print("[AutoUpdater] Update ready to install!");
			EmitSignal(SignalName.UpdateReady);
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[AutoUpdater] Error downloading update: {e.Message}");
			EmitSignal(SignalName.UpdateError, e.Message);
		}
	}
	public void ApplyUpdateAndRestart()
	{
		GD.Print("[AutoUpdater] Applying update...");
		
		try
		{
			var extractedPath = $"{_updatePath}/extracted";
			var currentDir = OS.GetExecutablePath().GetBaseDir();
			
			// Create updater script
			var scriptPath = CreateUpdaterScript(extractedPath, currentDir);
			
			// Launch updater and exit
			GD.Print("[AutoUpdater] Launching updater script...");
			
			if (OS.GetName() == "Windows")
			{
				OS.Execute("cmd.exe", new string[] { "/c", "start", scriptPath });
			}
			else
			{
				OS.Execute("sh", new string[] { scriptPath });
			}
			
			// Exit game to allow update
			GetTree().Quit();
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[AutoUpdater] Error applying update: {e.Message}");
			EmitSignal(SignalName.UpdateError, e.Message);
		}
	}
	
	// Helper: Get update manifest from server
	private async Task<Dictionary> GetUpdateManifest(string url)
	{
		try
		{
			var response = await _httpClient.GetAsync(url);
			if (!response.IsSuccessStatusCode) return null;
			
			var json = await response.Content.ReadAsStringAsync();
			var parser = new Json();
			
			if (parser.Parse(json) == Error.Ok)
			{
				return parser.Data.AsGodotDictionary();
			}
		}
		catch
		{
			// Silent fail, will try GitHub
		}
		
		return null;
	}
	
	// Helper: Get latest release from GitHub
	private async Task<Dictionary> GetGitHubLatestRelease()
	{
		try
		{
			var url = $"https://api.github.com/repos/{GitHubRepo}/releases/latest";
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("User-Agent", "GodotStation-Updater");
			
			var response = await _httpClient.GetAsync(url);
			if (!response.IsSuccessStatusCode) return null;
			
			var json = await response.Content.ReadAsStringAsync();
			var parser = new Json();
			
			if (parser.Parse(json) == Error.Ok)
			{
				var release = parser.Data.AsGodotDictionary();
				
				// Convert GitHub release format to our manifest format
				var manifest = new Dictionary
				{
					{ "version", release["tag_name"].ToString().TrimPrefix("v") },
					{ "build_date", release["published_at"].ToString() },
					{ "platforms", new Dictionary() }
				};
				
				var assets = release["assets"].AsGodotArray();
				var platforms = manifest["platforms"].AsGodotDictionary();
				
				foreach (Dictionary asset in assets)
				{
					var name = asset["name"].ToString().ToLower();
					
					if (name.Contains("windows"))
					{
						platforms["windows"] = new Dictionary
						{
							{ "url", asset["browser_download_url"].ToString() },
							{ "size", Convert.ToInt64(asset["size"]) }
						};
					}
					else if (name.Contains("linux"))
					{
						platforms["linux"] = new Dictionary
						{
							{ "url", asset["browser_download_url"].ToString() },
							{ "size", Convert.ToInt64(asset["size"]) }
						};
					}
				}
				
				return manifest;
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[AutoUpdater] GitHub API error: {e.Message}");
		}
		
		return null;
	}
	
	// Helper: Download file with progress reporting
	private async Task DownloadFileWithProgress(string url, string destination)
	{
		using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
		response.EnsureSuccessStatusCode();
		
		var totalBytes = response.Content.Headers.ContentLength ?? 0;
		var buffer = new byte[8192];
		var bytesRead = 0L;
		
		using var contentStream = await response.Content.ReadAsStreamAsync();
		using var fileStream = File.Create(destination);
		
		int read;
		while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
		{
			await fileStream.WriteAsync(buffer, 0, read);
			bytesRead += read;
			
			if (totalBytes > 0)
			{
				var progress = (float)bytesRead / totalBytes;
				CallDeferred(MethodName.EmitSignal, SignalName.UpdateDownloadProgress, progress);
			}
		}
	}
	
	// Helper: Extract zip file
	private void ExtractUpdate(string zipPath)
	{
		var extractPath = $"{_updatePath}/extracted";

		// Clean old extraction
		if (DirAccess.DirExistsAbsolute(extractPath))
		{
			DeleteDirectory(extractPath);
		}

		DirAccess.MakeDirRecursiveAbsolute(extractPath);

		// Use Godot's built-in ZIPReader
		var zip = new ZipReader();
		var error = zip.Open(zipPath);

		if (error != Error.Ok)
		{
			GD.PrintErr($"[AutoUpdater] Failed to open zip: {error}");
			return;
		}

		var files = zip.GetFiles();
		foreach (var file in files)
		{
			var data = zip.ReadFile(file);
			var outputPath = $"{extractPath}/{file}";

			// Create directory if needed
			var dir = outputPath.GetBaseDir();
			if (!DirAccess.DirExistsAbsolute(dir))
			{
				DirAccess.MakeDirRecursiveAbsolute(dir);
			}

			// Write file using System.IO
			using var outputFile = new System.IO.FileStream(
				outputPath,
				System.IO.FileMode.Create,
				System.IO.FileAccess.Write
			);
			outputFile.Write(data, 0, data.Length);
		}

		zip.Close();
		GD.Print($"[AutoUpdater] Extracted {files.Length} files");
	}
	// Helper: Create platform-specific updater script
	private string CreateUpdaterScript(string sourcePath, string targetPath)
	{
		if (OS.GetName() == "Windows")
		{
			var scriptPath = $"{_updatePath}/update.bat";
			var script = $@"@echo off
echo GodotStation Updater
echo Waiting for game to close...
timeout /t 2 /nobreak > nul

echo Applying update...
xcopy /E /I /Y ""{sourcePath}\*"" ""{targetPath}""

echo Update complete!
echo Restarting game...
timeout /t 2 /nobreak > nul

cd ""{targetPath}""
start """" ""GodotStation.exe""

del ""%~f0""
";
			
			File.WriteAllText(scriptPath, script);
			return scriptPath;
		}
		else // Linux
		{
			var scriptPath = $"{_updatePath}/update.sh";
			var script = $@"#!/bin/bash
echo ""GodotStation Updater""
echo ""Waiting for game to close...""
sleep 2

echo ""Applying update...""
cp -rf ""{sourcePath}""/* ""{targetPath}""

echo ""Update complete!""
echo ""Restarting game...""
sleep 2

cd ""{targetPath}""
chmod +x GodotStation.x86_64
./GodotStation.x86_64 &

rm ""$0""
";
			
			File.WriteAllText(scriptPath, script);
			
			// Make executable
			OS.Execute("chmod", new string[] { "+x", scriptPath });
			
			return scriptPath;
		}
	}
	
	// Helper: Compare versions (semantic versioning)
	private bool IsNewerVersion(string latest, string current)
	{
		try
		{
			var latestParts = latest.TrimPrefix("v").Split('.');
			var currentParts = current.TrimPrefix("v").Split('.');
			
			for (int i = 0; i < Math.Min(latestParts.Length, currentParts.Length); i++)
			{
				var latestNum = int.Parse(latestParts[i]);
				var currentNum = int.Parse(currentParts[i]);
				
				if (latestNum > currentNum) return true;
				if (latestNum < currentNum) return false;
			}
			
			return latestParts.Length > currentParts.Length;
		}
		catch
		{
			return false;
		}
	}
	
	// Helper: Get current platform
	private string GetCurrentPlatform()
	{
		var os = OS.GetName();
		
		if (os == "Windows")
			return "windows";
		else if (os == "Linux" || os == "FreeBSD" || os == "NetBSD" || os == "OpenBSD" || os == "BSD")
			return "linux";
		else if (os == "macOS")
			return "macos";
		
		return "unknown";
	}
	
	// Helper: Delete directory recursively
	private void DeleteDirectory(string path)
	{
		var dir = DirAccess.Open(path);
		if (dir != null)
		{
			dir.ListDirBegin();
			var fileName = dir.GetNext();
			
			while (fileName != "")
			{
				if (dir.CurrentIsDir())
				{
					if (fileName != "." && fileName != "..")
					{
						DeleteDirectory($"{path}/{fileName}");
					}
				}
				else
				{
					dir.Remove(fileName);
				}
				fileName = dir.GetNext();
			}
			
			dir.ListDirEnd();
			dir.Remove(path);
		}
	}
	
	public override void _ExitTree()
	{
		_httpClient?.Dispose();
	}
}
