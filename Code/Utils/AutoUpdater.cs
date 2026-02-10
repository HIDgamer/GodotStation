using Godot;
using Godot.Collections;
using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;

public partial class AutoUpdater : Node
{
	[Export] public string UpdateServerUrl = "http://132.145.130.83:8086/updates/version-manifest.json";
	[Export] public string GitHubRepo = "HIDgamer/GodotStation";
	[Export] public bool CheckOnStartup = true;
	[Export] public string CurrentVersion = "0.9.0";
	
	[Signal] public delegate void UpdateAvailableEventHandler(string newVersion);
	[Signal] public delegate void UpdateDownloadProgressEventHandler(float progress);
	[Signal] public delegate void UpdateReadyToInstallEventHandler();
	[Signal] public delegate void UpdateErrorEventHandler(string error);
	
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
		{
			DirAccess.MakeDirRecursiveAbsolute(_updatePath);
		}
		
		ApplyPendingUpdateIfExists();
		
		if (CheckOnStartup)
		{
			CallDeferred(MethodName.CheckForUpdates);
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
			GD.Print($"[AutoUpdater] Update applied successfully!");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AutoUpdater] Failed to apply update: {e.Message}");
		}
	}
	
	public async void CheckForUpdates()
	{
		if (_isDownloading)
			return;
		
		try
		{
			var manifest = await GetUpdateManifest();
			
			if (manifest == null)
			{
				EmitSignal(SignalName.UpdateError, "Could not fetch update info");
				return;
			}
			
			var latestVersion = manifest["version"].ToString();
			
			if (IsNewerVersion(latestVersion, CurrentVersion))
			{
				EmitSignal(SignalName.UpdateAvailable, latestVersion);
			}
		}
		catch (Exception e)
		{
			EmitSignal(SignalName.UpdateError, e.Message);
		}
	}
	
	public async void DownloadUpdate()
	{
		if (_isDownloading)
			return;
		
		_isDownloading = true;
		
		try
		{
			var manifest = await GetUpdateManifest();
			var platforms = manifest["platforms"].AsGodotDictionary();
			var platform = GetCurrentPlatform();
			
			if (!platforms.ContainsKey(platform))
			{
				EmitSignal(SignalName.UpdateError, $"No update for {platform}");
				_isDownloading = false;
				return;
			}
			
			var platformData = platforms[platform].AsGodotDictionary();
			var downloadUrl = platformData["url"].ToString();
			var zipPath = $"{_updatePath}/update.zip";
			
			await DownloadFileWithProgress(downloadUrl, zipPath);
			
			if (DirAccess.DirExistsAbsolute(_pendingUpdatePath))
			{
				DeleteDirectory(_pendingUpdatePath);
			}
			
			DirAccess.MakeDirRecursiveAbsolute(_pendingUpdatePath);
			ExtractZip(zipPath, _pendingUpdatePath);
			
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
	
	public void RestartToApplyUpdate()
	{
		OS.CreateInstance(new string[] { });
		GetTree().Quit();
	}
	
	private async Task<Dictionary> GetUpdateManifest()
	{
		try
		{
			var response = await _httpClient.GetAsync(UpdateServerUrl);
			if (response.IsSuccessStatusCode)
			{
				var json = await response.Content.ReadAsStringAsync();
				var parser = new Json();
				if (parser.Parse(json) == Error.Ok)
				{
					return parser.Data.AsGodotDictionary();
				}
			}
		}
		catch { }
		
		try
		{
			var url = $"https://api.github.com/repos/{GitHubRepo}/releases/latest";
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("User-Agent", "GodotStation");
			
			var response = await _httpClient.GetAsync(url);
			var json = await response.Content.ReadAsStringAsync();
			var parser = new Json();
			
			if (parser.Parse(json) == Error.Ok)
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
					
					if (name.Contains("windows"))
					{
						platforms["windows"] = new Dictionary
						{
							{ "url", asset["browser_download_url"].ToString() },
							{ "size", asset["size"] }
						};
					}
					else if (name.Contains("linux"))
					{
						platforms["linux"] = new Dictionary
						{
							{ "url", asset["browser_download_url"].ToString() },
							{ "size", asset["size"] }
						};
					}
				}
				
				return manifest;
			}
		}
		catch { }
		
		return null;
	}
	
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