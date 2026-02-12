using Godot;
using Godot.Collections;
using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;

public partial class AutoUpdater : Node
{
	[Export] public string UpdateServerUrl = "http://129.213.29.53:8086/updates/version-manifest.json";
	[Export] public string GitHubRepo = "HIDgamer/GodotStation";
	[Export] public bool CheckOnStartup = true;
	[Export] public string CurrentVersion = "0.9.0";
	[Export] public string UpdateUISceneUid = "uid://cdux206csw0ra";
	[Signal] public delegate void UpdateAvailableEventHandler(string version);
	[Signal] public delegate void UpdateDownloadProgressEventHandler(float progress);
	[Signal] public delegate void UpdateReadyToInstallEventHandler();
	[Signal] public delegate void UpdateErrorEventHandler(string message);
	private HttpClient _httpClient;
	private string _updatePath;
	private string _pendingUpdatePath;
	private bool _isDownloading = false;
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_updatePath = OS.GetUserDataDir() + "/updates";
		_pendingUpdatePath = _updatePath + "/pending";
		
		if (!DirAccess.DirExistsAbsolute(_updatePath))
			DirAccess.MakeDirRecursiveAbsolute(_updatePath);
		
		ApplyPendingUpdateIfExists();
		
		if (CheckOnStartup)
		{
			GetTree().CreateTimer(1.5f).Timeout += () => CheckForUpdates();
		}
	}
	
	private void ApplyPendingUpdateIfExists()
	{
		if (!DirAccess.DirExistsAbsolute(_pendingUpdatePath))
			return;
		
		var execDir = OS.GetExecutablePath().GetBaseDir();
		
		try
		{
			CopyDirectory(_pendingUpdatePath, execDir);
			DeleteDirectory(_pendingUpdatePath);
			GD.Print("[AutoUpdater] Update applied successfully!");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AutoUpdater] Failed to apply update: {e.Message}");
		}
	}
	
	private void ShowUpdateUI(string version)
	{
		GD.Print("[AutoUpdater] ShowUpdateUI called.");

		if (GetTree().Root.HasNode("UpdateNotificationUI"))
		{
			GD.Print("[AutoUpdater] UI already exists, skipping.");
			return;
		}

		var res = ResourceLoader.Load(UpdateUISceneUid);

		if (res == null)
		{
			GD.PrintErr($"[AutoUpdater] FAILED: ResourceLoader returned NULL for UID: {UpdateUISceneUid}");
			return;
		}

		if (res is not PackedScene uiScene)
		{
			GD.PrintErr($"[AutoUpdater] FAILED: Resource at {UpdateUISceneUid} is NOT a PackedScene. Type = {res.GetType()}");
			return;
		}

		var uiInstance = uiScene.Instantiate();
		uiInstance.Name = "UpdateNotificationUI";

		GD.Print("[AutoUpdater] Instanced UI successfully. Adding to root.");

		GetTree().Root.AddChild(uiInstance);

		if (uiInstance.HasMethod("initialize_with_data"))
		{
			uiInstance.Call("initialize_with_data", version);
		}
		else
		{
			GD.PrintErr("[AutoUpdater] UI scene has NO initialize_with_data method!");
		}
	}
	public async void CheckForUpdates()
	{
		if (_isDownloading) return;
		
		var manifest = await GetUpdateManifest();
		if (manifest == null) return;
		
		var latestVersion = manifest["version"].ToString();
		if (IsNewerVersion(latestVersion, CurrentVersion))
		{
			GD.Print($"[AutoUpdater] Update found: {latestVersion}. Instancing UI...");
			CallDeferred(MethodName.ShowUpdateUI, latestVersion);
		}
	}
	public async void DownloadUpdate()
	{
		if (_isDownloading) return;

		string execDir = OS.GetExecutablePath().GetBaseDir();
		if (!HasWriteAccess(execDir))
		{
			if (OS.GetName() == "Windows")
			{
				GetTree().Root.GetNode("UpdateNotificationUI").Call("show_permission_warning");
				return;
			}
			else
			{
				EmitSignal(SignalName.UpdateError, "Insufficient permissions to update game files.");
				return;
			}
		}

		_isDownloading = true;
		
		try
		{
			var manifest = await GetUpdateManifest();
			var platforms = manifest["platforms"].AsGodotDictionary();
			var platform = GetCurrentPlatform();
			
			if (!platforms.ContainsKey(platform))
			{
				EmitSignal(SignalName.UpdateError, $"No update for {platform}");
				return;
			}
			
			var platformData = platforms[platform].AsGodotDictionary();
			var downloadUrl = platformData["url"].ToString();
			var zipPath = Path.Combine(ProjectSettings.GlobalizePath(_updatePath), "update.zip");
			
			await DownloadFileWithProgress(downloadUrl, zipPath);
			
			string pendingAbsolute = ProjectSettings.GlobalizePath(_pendingUpdatePath);
			if (Directory.Exists(pendingAbsolute))
			{
				Directory.Delete(pendingAbsolute, true);
			}
			
			Directory.CreateDirectory(pendingAbsolute);
			ExtractZip(zipPath, pendingAbsolute);
			
			EmitSignal(SignalName.UpdateReadyToInstall);
		}
		catch (Exception e)
		{
			EmitSignal(SignalName.UpdateError, e.Message);
		}
		finally
		{
			_isDownloading = false;
		}
	}
	public void RequestAdminPrivileges()
	{
		string exePath = OS.GetExecutablePath();
		string[] args = OS.GetCmdlineArgs();
		
		System.Diagnostics.ProcessStartInfo startInfo = new System.Diagnostics.ProcessStartInfo
		{
			FileName = exePath,
			UseShellExecute = true,
			Verb = "runas",
			Arguments = string.Join(" ", args)
		};

		try
		{
			System.Diagnostics.Process.Start(startInfo);
			GetTree().Quit();
		}
		catch (Exception e)
		{
			GD.PrintErr("Elevation failed: " + e.Message);
		}
	}
	private bool HasWriteAccess(string directoryPath)
	{
		try
		{
			string absolutePath = ProjectSettings.GlobalizePath(directoryPath);
			if (!Directory.Exists(absolutePath))
			{
				Directory.CreateDirectory(absolutePath);
			}

			string testFile = Path.Combine(absolutePath, ".write_test");
			File.WriteAllText(testFile, "test");
			File.Delete(testFile);
			return true;
		}
		catch
		{
			return false;
		}
	}
	public void RestartToApplyUpdate()
	{
		OS.CreateInstance(new string[] { });
		GetTree().Quit();
	}
	
	private async Task<Dictionary> GetUpdateManifest()
	{
		GD.Print("[AutoUpdater] Fetching manifest...");
		try
		{
			using var response = await _httpClient.GetAsync(UpdateServerUrl + "?t=" + DateTime.Now.Ticks);
			if (response.IsSuccessStatusCode)
			{
				var jsonText = await response.Content.ReadAsStringAsync();
				var parser = new Json();
				if (parser.Parse(jsonText) == Error.Ok)
				{
					GD.Print("[AutoUpdater] Manifest source: Oracle");
					return parser.Data.AsGodotDictionary();
				}
			}
		}
		catch (Exception e) 
		{ 
			GD.Print($"[AutoUpdater] Oracle failed: {e.Message}"); 
		}

		try
		{
			var url = $"https://api.github.com/repos/{GitHubRepo}/releases/latest";
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("User-Agent", "GodotStation");
			
			var response = await _httpClient.GetAsync(url);
			if (response.IsSuccessStatusCode)
			{
				var jsonText = await response.Content.ReadAsStringAsync();
				var parser = new Json();
				if (parser.Parse(jsonText) == Error.Ok)
				{
					var release = parser.Data.AsGodotDictionary();
					var manifest = new Dictionary
					{
						{ "version", release["tag_name"].ToString().TrimPrefix("v") },
						{ "platforms", new Dictionary() }
					};
					
					var assets = release["assets"].AsGodotArray();
					var platforms = manifest["platforms"].AsGodotDictionary();
					
					foreach (Dictionary asset in assets)
					{
						var name = asset["name"].ToString().ToLower();
						string platformKey = name.Contains("windows") ? "windows" : name.Contains("linux") ? "linux" : "";
						
						if (!string.IsNullOrEmpty(platformKey))
						{
							platforms[platformKey] = new Dictionary
							{
								{ "url", asset["browser_download_url"].ToString() },
								{ "size", asset["size"] }
							};
						}
					}
					GD.Print("[AutoUpdater] Manifest source: GitHub API");
					return manifest;
				}
			}
		}
		catch (Exception e) 
		{ 
			GD.Print($"[AutoUpdater] GitHub failed: {e.Message}"); 
		}

		return null;
	}
	private async Task DownloadFileWithProgress(string url, string destination)
	{
		using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
		response.EnsureSuccessStatusCode();
		
		var totalBytes = response.Content.Headers.ContentLength ?? 0;
		var buffer = new byte[131072];
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
				CallDeferred(MethodName.EmitSignal, SignalName.UpdateDownloadProgress, (float)bytesRead / totalBytes);
			}
		}
	}
	
	private void ExtractZip(string zipPath, string extractPath)
	{
		var zip = new ZipReader();
		if (zip.Open(zipPath) != Error.Ok)
			return;
		
		var files = zip.GetFiles();
		foreach (var file in files)
		{
			var data = zip.ReadFile(file);
			var outputPath = $"{extractPath}/{file}";
			var dir = outputPath.GetBaseDir();
			
			if (!DirAccess.DirExistsAbsolute(dir))
			{
				DirAccess.MakeDirRecursiveAbsolute(dir);
			}
			
			System.IO.File.WriteAllBytes(outputPath, data);
		}
		
		zip.Close();
	}
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
	
	private string GetCurrentPlatform()
	{
		var os = OS.GetName();
		if (os == "Windows") return "windows";
		if (os.Contains("Linux") || os.Contains("BSD")) return "linux";
		if (os == "macOS") return "macos";
		return "unknown";
	}
	
	private void CopyDirectory(string source, string dest)
	{
		var dir = DirAccess.Open(source);
		if (dir == null) return;
		
		dir.ListDirBegin();
		var fileName = dir.GetNext();
		
		while (fileName != "")
		{
			if (fileName != "." && fileName != "..")
			{
				var sourcePath = $"{source}/{fileName}";
				var destPath = $"{dest}/{fileName}";
				
				if (dir.CurrentIsDir())
				{
					if (!DirAccess.DirExistsAbsolute(destPath))
					{
						DirAccess.MakeDirAbsolute(destPath);
					}
					CopyDirectory(sourcePath, destPath);
				}
				else
				{
					DirAccess.CopyAbsolute(sourcePath, destPath);
				}
			}
			fileName = dir.GetNext();
		}
		
		dir.ListDirEnd();
	}
	
	private void DeleteDirectory(string path)
	{
		var dir = DirAccess.Open(path);
		if (dir == null) return;
		
		dir.ListDirBegin();
		var fileName = dir.GetNext();
		
		while (fileName != "")
		{
			if (fileName != "." && fileName != "..")
			{
				var fullPath = $"{path}/{fileName}";
				if (dir.CurrentIsDir())
				{
					DeleteDirectory(fullPath);
				}
				else
				{
					dir.Remove(fileName);
				}
			}
			fileName = dir.GetNext();
		}
		
		dir.ListDirEnd();
		DirAccess.RemoveAbsolute(path);
	}
	
	public override void _ExitTree()
	{
		_httpClient?.Dispose();
	}
}
