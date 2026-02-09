using Godot;
using Godot.Collections;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;

public partial class AccountManager : Node
{
	[Export] public string ApiUrl = "http://150.136.90.194:3000";
	
	[Signal] public delegate void LoginSuccessEventHandler(Dictionary userData, string token);
	[Signal] public delegate void LoginFailedEventHandler(string error);
	[Signal] public delegate void RegisterSuccessEventHandler(Dictionary userData, string token);
	[Signal] public delegate void RegisterFailedEventHandler(string error);
	
	private HttpClient _httpClient;
	private string _authToken = "";
	private Dictionary _currentUser = new();
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		LoadSavedCredentials();
	}
	
	public bool IsLoggedIn()
	{
		return !string.IsNullOrEmpty(_authToken);
	}
	
	public string GetAuthToken()
	{
		return _authToken;
	}
	
	public Dictionary GetCurrentUser()
	{
		return _currentUser;
	}
	
	public string GetUsername()
	{
		return _currentUser.ContainsKey("username") ? (string)_currentUser["username"] : "";
	}
	
	public int GetUserId()
	{
		if (_currentUser.ContainsKey("id"))
		{
			Variant v = _currentUser["id"];
			return v.VariantType switch
			{
				Variant.Type.Int => v.AsInt32(),
				Variant.Type.Float => (int)v.AsSingle(),
				Variant.Type.String => int.TryParse(v.AsString(), out var n) ? n : 0,
				_ => 0
			};
		}

		return 0;
	}
	
	// Register new account
	public async void Register(string username, string email, string password)
	{
		try
		{
			var data = new Dictionary
			{
				{ "username", username },
				{ "email", email },
				{ "password", password }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/auth/register", content);
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("token") && result.ContainsKey("user"))
					{
						_authToken = result["token"].ToString();
						_currentUser = result["user"].AsGodotDictionary();
						
						SaveCredentials(username, _authToken);
						EmitSignal(SignalName.RegisterSuccess, _currentUser, _authToken);
						GD.Print($"[AccountManager] Registration successful: {username}");
					}
				}
			}
			else
			{
				var error = ParseError(responseText);
				EmitSignal(SignalName.RegisterFailed, error);
				GD.PrintErr($"[AccountManager] Registration failed: {error}");
			}
		}
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.RegisterFailed, errorMsg);
			GD.PrintErr($"[AccountManager] {errorMsg}");
		}
	}
	
	// Login to existing account
	public async void Login(string username, string password)
	{
		try
		{
			var data = new Dictionary
			{
				{ "username", username },
				{ "password", password }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/auth/login", content);
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("token") && result.ContainsKey("user"))
					{
						_authToken = result["token"].ToString();
						_currentUser = result["user"].AsGodotDictionary();
						
						SaveCredentials(username, _authToken);
						EmitSignal(SignalName.LoginSuccess, _currentUser, _authToken);
						GD.Print($"[AccountManager] Login successful: {username}");
					}
				}
			}
			else
			{
				var error = ParseError(responseText);
				EmitSignal(SignalName.LoginFailed, error);
				GD.PrintErr($"[AccountManager] Login failed: {error}");
			}
		}
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.LoginFailed, errorMsg);
			GD.PrintErr($"[AccountManager] {errorMsg}");
		}
	}
	
	// Auto-login with saved token
	public async void AutoLogin()
	{
		if (string.IsNullOrEmpty(_authToken))
		{
			EmitSignal(SignalName.LoginFailed, "No saved credentials");
			return;
		}
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_authToken}");
			
			var response = await _httpClient.GetAsync($"{ApiUrl}/api/auth/me");
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("user"))
					{
						_currentUser = result["user"].AsGodotDictionary();
						
						EmitSignal(SignalName.LoginSuccess, _currentUser, _authToken);
						GD.Print($"[AccountManager] Auto-login successful");
					}
				}
			}
			else
			{
				ClearCredentials();
				EmitSignal(SignalName.LoginFailed, "Session expired");
			}
		}
		catch (System.Exception e)
		{
			EmitSignal(SignalName.LoginFailed, $"Connection error: {e.Message}");
		}
	}
	
	// Logout
	public void Logout()
	{
		_authToken = "";
		_currentUser.Clear();
		ClearCredentials();
		GD.Print("[AccountManager] Logged out");
	}
	
	// Save credentials to file
	private void SaveCredentials(string username, string token)
	{
		var config = new ConfigFile();
		config.SetValue("auth", "username", username);
		config.SetValue("auth", "token", token);
		config.Save("user://auth.cfg");
	}
	
	// Load saved credentials
	private void LoadSavedCredentials()
	{
		var config = new ConfigFile();
		var error = config.Load("user://auth.cfg");
		
		if (error == Error.Ok)
		{
			_authToken = (string)config.GetValue("auth", "token", "");
			if (!string.IsNullOrEmpty(_authToken))
			{
				GD.Print("[AccountManager] Found saved credentials, attempting auto-login...");
				CallDeferred(MethodName.AutoLogin);
			}
		}
	}
	
	// Clear saved credentials
	private void ClearCredentials()
	{
		var config = new ConfigFile();
		config.SetValue("auth", "username", "");
		config.SetValue("auth", "token", "");
		config.Save("user://auth.cfg");
	}
	
	// Parse error from response
	private string ParseError(string responseText)
	{
		try
		{
			var jsonParser = new Json();
			if (jsonParser.Parse(responseText) == Error.Ok)
			{
				var result = jsonParser.Data.AsGodotDictionary();
				if (result.ContainsKey("error"))
				{
					return result["error"].ToString();
				}
			}
		}
		catch
		{
			// Ignore parsing errors
		}
		return "Unknown error occurred";
	}
	
	public override void _ExitTree()
	{
		_httpClient?.Dispose();
	}
}
