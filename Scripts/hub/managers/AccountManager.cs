using Godot;
using Godot.Collections;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;

public partial class AccountManager : Node
{
	[Export] public string ApiUrl = "https://godotstation.duckdns.org";
	[Export] public string DiscordClientId = "1470420296040189995";
	[Export] public string DiscordRedirectUri = "http://127.0.0.1:8080";

	[Signal] public delegate void LoginSuccessEventHandler(Dictionary userData, string token);
	[Signal] public delegate void LoginFailedEventHandler(string error);
	[Signal] public delegate void LogoutEventHandler();
	[Signal] public delegate void TokenRotatedEventHandler(string newToken);

	private const string TOKEN_SAVE_PATH = "user://auth_token.dat";

	private HttpClient _httpClient;
	private Dictionary _userData = new();
	private string _authToken = "";
	private HttpServer _callbackServer;

	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_httpClient.Timeout = TimeSpan.FromSeconds(10);

		CallDeferred(MethodName.TryAutoLogin);
	}

	private async void TryAutoLogin()
	{
		var savedToken = LoadToken();

		if (!string.IsNullOrEmpty(savedToken))
		{
			GD.Print("[AccountManager] Found saved token, attempting auto-login...");
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
						GD.Print($"[AccountManager] Token verified for user: {GetUsername()}");
						return true;
					}
				}
			}
		}
		catch (TaskCanceledException)
		{
			GD.PrintErr("[AccountManager] Token verification timed out");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Token verification failed: {e.Message}");
		}

		return false;
	}

	// ── Token persistence (AES-256-GCM, machine-local key) ────────────────────

	private void SaveToken(string token)
	{
		try
		{
			using var file = FileAccess.Open(TOKEN_SAVE_PATH, FileAccess.ModeFlags.Write);
			if (file != null)
			{
				file.StoreString(CryptoUtils.Encrypt(token));
				GD.Print("[AccountManager] Token saved (AES-256-GCM)");
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
					return CryptoUtils.Decrypt(file.GetAsText());
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

	// ── Token rotation (called by LobbyManager when server pushes a new token) ──

	public void UpdateToken(string newToken)
	{
		if (string.IsNullOrEmpty(newToken))
		{
			GD.PrintErr("[AccountManager] UpdateToken called with empty token — ignoring");
			return;
		}

		_authToken = newToken;
		SaveToken(newToken);
		GD.Print("[AccountManager] Token rotated and saved successfully");
		EmitSignal(SignalName.TokenRotated, newToken);
	}

	// ── Public accessors ───────────────────────────────────────────────────────

	public bool IsLoggedIn() => !string.IsNullOrEmpty(_authToken);
	public string GetAuthToken() => _authToken;

	public int GetUserId()
	{
		return _userData.ContainsKey("id") ? _userData["id"].AsInt32() : 0;
	}

	public string GetUsername()
	{
		return _userData.ContainsKey("username") ? _userData["username"].ToString() : "";
	}

	public string GetDiscordTag()
	{
		if (_userData.ContainsKey("discord_tag"))
			return _userData["discord_tag"].ToString();

		if (_userData.ContainsKey("global_name"))
		{
			var globalName = _userData["global_name"].ToString();
			if (!string.IsNullOrWhiteSpace(globalName))
				return globalName;
		}

		if (_userData.ContainsKey("username"))
		{
			var username = _userData["username"].ToString();
			if (_userData.ContainsKey("discriminator"))
			{
				var discriminator = _userData["discriminator"].ToString();
				if (!string.IsNullOrWhiteSpace(discriminator) && discriminator != "0")
					return $"{username}#{discriminator}";
			}
			return username;
		}

		return "";
	}

	// ── Discord OAuth flow ─────────────────────────────────────────────────────

	public void StartDiscordLogin()
	{
		StartCallbackServer();
		OS.ShellOpen($"{ApiUrl}/api/auth/discord");
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
		GD.Print($"[AccountManager] Callback received. Path: {path}");

		if (!query.ContainsKey("code"))
		{
			GD.PrintErr("[AccountManager] ERROR: 'code' parameter missing in callback URL.");
			EmitSignal(SignalName.LoginFailed, "Authentication callback missing code");
			return;
		}

		var code = query["code"].ToString();
		GD.Print("[AccountManager] One-time code received, exchanging for token...");

		try
		{
			_httpClient.DefaultRequestHeaders.Clear();

			var exchangePayload = new Godot.Collections.Dictionary { { "code", code } };
			var json = Json.Stringify(exchangePayload);
			var content = new StringContent(json, Encoding.UTF8, "application/json");

			var response = await _httpClient.PostAsync($"{ApiUrl}/api/auth/exchange", content);
			var responseText = await response.Content.ReadAsStringAsync();

			if (!response.IsSuccessStatusCode)
			{
				GD.PrintErr($"[AccountManager] Code exchange failed: {response.StatusCode}");
				EmitSignal(SignalName.LoginFailed, "Code exchange failed — please try again");
				return;
			}

			var parser = new Json();
			if (parser.Parse(responseText) != Error.Ok)
			{
				EmitSignal(SignalName.LoginFailed, "Invalid server response");
				return;
			}

			var result = parser.Data.AsGodotDictionary();
			if (!result.ContainsKey("token"))
			{
				EmitSignal(SignalName.LoginFailed, "Server response missing token");
				return;
			}

			_authToken = result["token"].ToString();
			SaveToken(_authToken);

			// Verify token and load user data
			bool valid = await VerifyToken(_authToken);
			if (valid)
			{
				GD.Print("[AccountManager] Login successful!");
				EmitSignal(SignalName.LoginSuccess, _userData, _authToken);
			}
			else
			{
				_authToken = "";
				DeleteToken();
				EmitSignal(SignalName.LoginFailed, "Token verification failed");
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[AccountManager] Code exchange exception: {e.Message}");
			EmitSignal(SignalName.LoginFailed, "Connection error during login");
		}
		finally
		{
			await Task.Delay(500);
			_callbackServer?.Stop();
		}
	}

	// ── Logout ─────────────────────────────────────────────────────────────────

	public event Action LoggedOutSuccess;

	public void RequestLogout()
	{
		_authToken = "";
		_userData.Clear();
		DeleteToken();
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

// ── Local HTTP callback server ─────────────────────────────────────────────────

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
			GD.Print($"[HttpServer] ✔ Listening on port {Port}");
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
			CallDeferred(MethodName.ProcessConnection, connection);
		}
	}

	private async void ProcessConnection(StreamPeerTcp connection)
	{
		try
		{
			int maxWait = 100;
			int waited = 0;

			while (connection.GetAvailableBytes() == 0 && waited < maxWait)
			{
				await Task.Delay(16);
				waited++;
			}

			if (connection.GetAvailableBytes() == 0)
			{
				GD.PrintErr("[HttpServer] Timeout waiting for data");
				connection.DisconnectFromHost();
				return;
			}

			// Cap incoming request to 8 KB — we only need a short GET with query params
			int bytesAvailable = Math.Min(connection.GetAvailableBytes(), 8192);
			var result = connection.GetData(bytesAvailable);
			Error readError = (Error)(long)result[0];

			if (readError != Error.Ok)
			{
				connection.DisconnectFromHost();
				return;
			}

			byte[] data = (byte[])result[1];
			string request = Encoding.UTF8.GetString(data);

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
						foreach (var param in pathParts[1].Split('&'))
						{
							var kv = param.Split('=');
							if (kv.Length == 2)
							{
								string key = Uri.UnescapeDataString(kv[0]);
								string value = Uri.UnescapeDataString(kv[1]);
								// Never log the code or token values
								query[key] = value;
							}
						}
					}

					CallDeferred(MethodName.EmitRequestSignal, path, query);

					// Success page — no token/code values are written here
					string body = @"<!DOCTYPE html>
<html>
<head>
  <meta charset='UTF-8'>
  <title>Authentication Success</title>
  <style>
    body { background:#23272a; color:white; text-align:center; padding:50px; font-family:sans-serif; }
    h1 { color:#4CAF50; }
    p  { color:#aaa; }
  </style>
</head>
<body>
  <h1>✔ Authentication Successful!</h1>
  <p>You are now logged in. You may close this tab.</p>
  <script>
    function tryClose(){try{window.open('','_self','').close();}catch(e){}try{window.close();}catch(e){}}
    tryClose();
    setTimeout(tryClose, 500);
  </script>
</body>
</html>";

					byte[] bodyBytes = Encoding.UTF8.GetBytes(body);
					string responseHeaders =
						"HTTP/1.1 200 OK\r\n" +
						"Content-Type: text/html; charset=utf-8\r\n" +
						"Content-Length: " + bodyBytes.Length + "\r\n" +
						"Connection: close\r\n" +
						// Prevent the browser from caching or leaking the code via Referer
						"Cache-Control: no-store\r\n" +
						"Referrer-Policy: no-referrer\r\n" +
						"\r\n";

					byte[] responseHeaderBytes = Encoding.UTF8.GetBytes(responseHeaders);
					byte[] fullResponse = new byte[responseHeaderBytes.Length + bodyBytes.Length];
					System.Array.Copy(responseHeaderBytes, 0, fullResponse, 0, responseHeaderBytes.Length);
					System.Array.Copy(bodyBytes, 0, fullResponse, responseHeaderBytes.Length, bodyBytes.Length);

					connection.PutData(fullResponse);
					await Task.Delay(200);
				}
			}

			connection.DisconnectFromHost();
		}
		catch (Exception e)
		{
			GD.PrintErr($"[HttpServer] Exception: {e.Message}");
			connection.DisconnectFromHost();
		}
	}

	private void EmitRequestSignal(string path, Dictionary query)
	{
		EmitSignal(SignalName.RequestReceived, path, query);
	}

	public override void _ExitTree() => Stop();
}