using Godot;
using Godot.Collections;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;

public partial class AccountManager : Node
{
	[Export] public string ApiUrl = "http://129.213.29.53:8085";
	[Export] public string DiscordClientId = "1470420296040189995";
	[Export] public string DiscordRedirectUri = "http://127.0.0.1:8080";
	
	[Signal] public delegate void LoginSuccessEventHandler(Dictionary userData, string token);
	[Signal] public delegate void LoginFailedEventHandler(string error);
	[Signal] public delegate void LogoutEventHandler();
	
	private const string TOKEN_SAVE_PATH = "user://auth_token.dat";
	
	private HttpClient _httpClient;
	private Dictionary _userData = new();
	private string _authToken = "";
	private HttpServer _callbackServer;
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		
		// Try to auto-login with saved token
		CallDeferred(MethodName.TryAutoLogin);
	}
	
	private async void TryAutoLogin()
	{
		var savedToken = LoadToken();
		
		if (!string.IsNullOrEmpty(savedToken))
		{
			GD.Print("[AccountManager] Found saved token, attempting auto-login...");
			
			// Verify token is still valid
			bool isValid = await VerifyToken(savedToken);
			
			if (isValid)
			{
				_authToken = savedToken;
				GD.Print("[AccountManager] Auto-login successful!");
				EmitSignal(SignalName.LoginSuccess, _userData, _authToken);
			}
			else
			{
				GD.Print("[AccountManager] Saved token expired or invalid");
				DeleteToken();
			}
		}
	}
	
	private async Task<bool> VerifyToken(string token)
	{
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {token}");
			
			var response = await _httpClient.GetAsync($"{ApiUrl}/api/auth/me");
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var parser = new Json();
				if (parser.Parse(responseText) == Error.Ok)
				{
					var result = parser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("user"))
					{
						_userData = result["user"].AsGodotDictionary();
						return true;
					}
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Token verification failed: {e.Message}");
		}
		
		return false;
	}
	
	private void SaveToken(string token)
	{
		try
		{
			using var file = FileAccess.Open(TOKEN_SAVE_PATH, FileAccess.ModeFlags.Write);
			if (file != null)
			{
				var encrypted = EncryptToken(token);
				file.StoreString(encrypted);
				GD.Print("[AccountManager] Token saved");
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Failed to save token: {e.Message}");
		}
	}
	
	private string LoadToken()
	{
		try
		{
			if (FileAccess.FileExists(TOKEN_SAVE_PATH))
			{
				using var file = FileAccess.Open(TOKEN_SAVE_PATH, FileAccess.ModeFlags.Read);
				if (file != null)
				{
					var encrypted = file.GetAsText();
					return DecryptToken(encrypted);
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Failed to load token: {e.Message}");
		}
		
		return "";
	}
	
	private void DeleteToken()
	{
		try
		{
			if (FileAccess.FileExists(TOKEN_SAVE_PATH))
			{
				DirAccess.RemoveAbsolute(TOKEN_SAVE_PATH);
				GD.Print("[AccountManager] Token deleted");
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Failed to delete token: {e.Message}");
		}
	}
	
	// Simple XOR encryption/decryption
	private string EncryptToken(string token)
	{
		const string key = "GSnebula2025";
		var result = new StringBuilder();
		
		for (int i = 0; i < token.Length; i++)
		{
			result.Append((char)(token[i] ^ key[i % key.Length]));
		}
		
		return Convert.ToBase64String(Encoding.UTF8.GetBytes(result.ToString()));
	}
	
	private string DecryptToken(string encrypted)
	{
		try
		{
			var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(encrypted));
			const string key = "GSnebula2025";
			var result = new StringBuilder();
			
			for (int i = 0; i < decoded.Length; i++)
			{
				result.Append((char)(decoded[i] ^ key[i % key.Length]));
			}
			
			return result.ToString();
		}
		catch
		{
			return "";
		}
	}
	
	public bool IsLoggedIn()
	{
		return !string.IsNullOrEmpty(_authToken);
	}
	
	public string GetAuthToken()
	{
		return _authToken;
	}
	
	public int GetUserId()
	{
		if (_userData.ContainsKey("id"))
		{
			return _userData["id"].AsInt32();
		}
		return 0;
	}
	
	public string GetUsername()
	{
		return _userData.ContainsKey("username") ? _userData["username"].ToString() : "";
	}
	
	public void StartDiscordLogin()
	{
		StartCallbackServer();
		string serverAuthUrl = $"{ApiUrl}/api/auth/discord";
		OS.ShellOpen(serverAuthUrl);
		GD.Print("[AccountManager] Opening Discord auth in browser...");
	}
	
	private void StartCallbackServer()
	{
		if (_callbackServer != null)
		{
			_callbackServer.Stop();
			_callbackServer.QueueFree();
		}
		
		_callbackServer = new HttpServer();
		_callbackServer.Port = 8080;
		_callbackServer.RequestReceived += OnCallbackReceived;
		AddChild(_callbackServer);
		_callbackServer.Start();
		GD.Print("[AccountManager] Local callback server started on port 8080");
	}
	
	private async void OnCallbackReceived(string path, Dictionary query)
	{
		GD.Print($"[AccountManager] Callback received! Path: {path}");
		GD.Print($"[AccountManager] Query parameters: {string.Join(", ", query.Keys)}");
		
		if (query.ContainsKey("val"))
		{
			_authToken = query["val"].ToString();
			_userData = new Dictionary { { "username", "Player" } };
			
			// Save token for auto-login next time
			SaveToken(_authToken);
			
			GD.Print($"[AccountManager] SUCCESS: Token received! Token: {_authToken.Substring(0, Math.Min(20, _authToken.Length))}...");
			EmitSignal(SignalName.LoginSuccess, _userData, _authToken);
			
			await Task.Delay(500);
			_callbackServer?.Stop();
		}
		else
		{
			GD.Print("[AccountManager] ERROR: 'val' parameter missing in URL.");
			GD.Print($"[AccountManager] Available parameters: {string.Join(", ", query.Keys)}");
			EmitSignal(SignalName.LoginFailed, "Authentication callback missing token");
		}
	}
	
	public event Action LoggedOutSuccess;
	
	public void RequestLogout()
	{
		_authToken = "";
		_userData.Clear();
		DeleteToken(); // Delete saved token on logout
		EmitSignal(SignalName.Logout); 
		LoggedOutSuccess?.Invoke();
		
		GD.Print("[AccountManager] Logged out");
	}
	
	public override void _ExitTree()
	{
		_callbackServer?.Stop();
		_httpClient?.Dispose();
	}
}

public partial class HttpServer : Node
{
	[Signal] public delegate void RequestReceivedEventHandler(string path, Dictionary query);
	
	public int Port { get; set; } = 8080;
	
	private TcpServer _server;
	private bool _running = false;
	
	public void Start()
	{
		_server = new TcpServer();
		Error err = _server.Listen((ushort)Port);
		
		if (err == Error.Ok)
		{
			_running = true;
			GD.Print($"[HttpServer] ✓ Successfully listening on port {Port}");
		}
		else
		{
			GD.PrintErr($"[HttpServer] ✗ Failed to listen on port {Port}: {err}");
		}
	}
	
	public void Stop()
	{
		_running = false;
		_server?.Stop();
		GD.Print("[HttpServer] Stopped");
	}
	
	public override void _Process(double delta)
	{
		if (!_running || _server == null) return;
		
		if (_server.IsConnectionAvailable())
		{
			var connection = _server.TakeConnection();
			GD.Print("[HttpServer] New connection received!");
			
			// Process the connection in the next frame to avoid blocking
			CallDeferred(MethodName.ProcessConnection, connection);
		}
	}
	
	private async void ProcessConnection(StreamPeerTcp connection)
	{
		try
		{
			// Wait for data with timeout
			int maxWaitFrames = 100; // ~1.6 seconds at 60fps
			int waitedFrames = 0;
			
			while (connection.GetAvailableBytes() == 0 && waitedFrames < maxWaitFrames)
			{
				await Task.Delay(16); // ~1 frame at 60fps
				waitedFrames++;
			}
			
			if (connection.GetAvailableBytes() == 0)
			{
				GD.PrintErr("[HttpServer] Timeout waiting for data");
				connection.DisconnectFromHost();
				return;
			}
			
			// Read the HTTP request
			int bytesAvailable = connection.GetAvailableBytes();
			GD.Print($"[HttpServer] Reading {bytesAvailable} bytes");
			
			Godot.Collections.Array result = connection.GetData(bytesAvailable);
			
			// GetData returns [Error, byte[]]
			Error readError = (Error)(long)result[0];
			if (readError != Error.Ok)
			{
				GD.PrintErr($"[HttpServer] Error reading data: {readError}");
				connection.DisconnectFromHost();
				return;
			}
			
			byte[] data = (byte[])result[1];
			string request = Encoding.UTF8.GetString(data);
			GD.Print($"[HttpServer] Received request:\n{request.Substring(0, Math.Min(200, request.Length))}");
			
			// Parse HTTP request
			string[] lines = request.Split('\n');
			if (lines.Length > 0 && lines[0].Contains("GET"))
			{
				var parts = lines[0].Trim().Split(' ');
				if (parts.Length >= 2)
				{
					var fullPath = parts[1];
					var pathParts = fullPath.Split('?');
					var path = pathParts[0];
					var query = new Dictionary();
					
					if (pathParts.Length > 1)
					{
						GD.Print($"[HttpServer] Query string: {pathParts[1]}");
						foreach (var param in pathParts[1].Split('&'))
						{
							var kv = param.Split('=');
							if (kv.Length == 2)
							{
								string key = Uri.UnescapeDataString(kv[0]);
								string value = Uri.UnescapeDataString(kv[1]);
								query[key] = value;
								GD.Print($"[HttpServer] Parsed param: {key} = {value.Substring(0, Math.Min(20, value.Length))}...");
							}
						}
					}
					
					// Emit signal on main thread
					CallDeferred(MethodName.EmitRequestSignal, path, query);
					
					// Send success response with auto-close script
					string body = @"<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Authentication Success</title>
    <style>
        body { 
            background: #23272a; 
            color: white; 
            text-align: center; 
            padding: 50px; 
            font-family: sans-serif; 
        }
        h1 { 
            color: #4CAF50; 
            margin-bottom: 20px;
            animation: glow 1.5s ease-in-out infinite;
        }
        @keyframes glow {
            0%, 100% { text-shadow: 0 0 10px #4CAF50; }
            50% { text-shadow: 0 0 20px #4CAF50, 0 0 30px #4CAF50; }
        }
        p { font-size: 18px; }
        .close-hint { 
            margin-top: 30px; 
            font-size: 14px; 
            color: #888; 
        }
        .countdown {
            font-size: 48px;
            color: #4CAF50;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>✓ Authentication Successful!</h1>
    <p>You have been logged in successfully.</p>
    <p>You can now return to the game.</p>
    <div class='countdown' id='countdown'>3</div>
    <div class='close-hint'>This window will close automatically...</div>
    <script>
        let count = 3;
        const countdownEl = document.getElementById('countdown');
        
        const interval = setInterval(() => {
            count--;
            if (count > 0) {
                countdownEl.textContent = count;
            } else {
                clearInterval(interval);
                countdownEl.textContent = '✓';
                
                // Try multiple methods to close the window
                setTimeout(() => {
                    window.open('', '_self').close();
                    window.close();
                    
                    // If nothing works, show a message
                    setTimeout(() => {
                        document.body.innerHTML = '<h1>You can safely close this window now</h1>';
                    }, 500);
                }, 500);
            }
        }, 1000);
    </script>
</body>
</html>";

					byte[] bodyBytes = Encoding.UTF8.GetBytes(body);
					string response = "HTTP/1.1 200 OK\r\n" +
									"Content-Type: text/html; charset=utf-8\r\n" +
									"Content-Length: " + bodyBytes.Length + "\r\n" +
									"Connection: close\r\n" +
									"Access-Control-Allow-Origin: *\r\n" +
									"\r\n";
					
					byte[] responseBytes = Encoding.UTF8.GetBytes(response);
					byte[] fullResponse = new byte[responseBytes.Length + bodyBytes.Length];
					System.Array.Copy(responseBytes, 0, fullResponse, 0, responseBytes.Length);
					System.Array.Copy(bodyBytes, 0, fullResponse, responseBytes.Length, bodyBytes.Length);
					
					Error putError = connection.PutData(fullResponse);
					if (putError != Error.Ok)
					{
						GD.PrintErr($"[HttpServer] Error sending response: {putError}");
					}
					else
					{
						GD.Print("[HttpServer] Response sent successfully!");
					}
					
					// Wait a bit for the response to be sent
					await Task.Delay(200);
				}
			}
			
			connection.DisconnectFromHost();
		}
		catch (Exception e)
		{
			GD.PrintErr($"[HttpServer] Exception processing connection: {e.Message}\n{e.StackTrace}");
			connection.DisconnectFromHost();
		}
	}
	
	private void EmitRequestSignal(string path, Dictionary query)
	{
		GD.Print($"[HttpServer] Emitting RequestReceived signal for path: {path}");
		EmitSignal(SignalName.RequestReceived, path, query);
	}
	
	public override void _ExitTree()
	{
		Stop();
	}
}
