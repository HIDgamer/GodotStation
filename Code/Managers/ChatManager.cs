using Godot;
using Godot.Collections;
using System;
using System.Text;
using System.Threading.Tasks;
using HttpClient = System.Net.Http.HttpClient;
using StringContent = System.Net.Http.StringContent;
using Array = Godot.Collections.Array;

public partial class ChatManager : Node
{
	[Export] public string ApiUrl = "https://godotstation.duckdns.org";
	
	[Signal] public delegate void MessageReceivedEventHandler(Dictionary message);
	[Signal] public delegate void MessageSentEventHandler(Dictionary message);
	[Signal] public delegate void MessageFailedEventHandler(string error);
	[Signal] public delegate void ChatHistoryLoadedEventHandler(int friendId, Array messages);
	
	private HttpClient _httpClient;
	private AccountManager _accountManager;
	private System.Collections.Generic.Dictionary<int, Array> _chatHistories = new();
	
	public override void _Ready()
	{
		_httpClient = new HttpClient();
		_accountManager = GetNode<AccountManager>("/root/AccountManager");
		_accountManager.Logout += OnLogout;
	}
	
	private void OnLogout()
	{
		_chatHistories.Clear();
	}
	
	// Send a chat message to a friend
	public async void SendMessage(int receiverId, string message)
	{
		if (!_accountManager.IsLoggedIn())
		{
			EmitSignal(SignalName.MessageFailed, "Not logged in");
			return;
		}
		
		if (string.IsNullOrEmpty(message) || message.Trim().Length == 0)
		{
			EmitSignal(SignalName.MessageFailed, "Message cannot be empty");
			return;
		}
		
		if (message.Length > 500)
		{
			EmitSignal(SignalName.MessageFailed, "Message too long (max 500 characters)");
			return;
		}
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var data = new Dictionary
			{
				{ "receiver_id", receiverId },
				{ "message", message.Trim() }
			};
			
			var json = Json.Stringify(data);
			var content = new StringContent(json, Encoding.UTF8, "application/json");
			
			var response = await _httpClient.PostAsync($"{ApiUrl}/api/chat/send", content);
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("message"))
					{
						var messageData = result["message"].AsGodotDictionary();
						
						AddMessageToHistory(receiverId, messageData);
						
						EmitSignal(SignalName.MessageSent, messageData);
						GD.Print($"[ChatManager] Message sent to user {receiverId}");
					}
				}
			}
			else
			{
				var error = ParseError(responseText);
				EmitSignal(SignalName.MessageFailed, error);
				GD.PrintErr($"[ChatManager] Send message failed: {error}");
			}
		}
		catch (System.Exception e)
		{
			var errorMsg = $"Connection error: {e.Message}";
			EmitSignal(SignalName.MessageFailed, errorMsg);
			GD.PrintErr($"[ChatManager] {errorMsg}");
		}
	}
	
	public async void LoadChatHistory(int friendId, int limit = 50)
	{
		if (!_accountManager.IsLoggedIn())
			return;
		
		try
		{
			_httpClient.DefaultRequestHeaders.Clear();
			_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_accountManager.GetAuthToken()}");
			
			var response = await _httpClient.GetAsync($"{ApiUrl}/api/chat/history?friend_id={friendId}&limit={limit}");
			var responseText = await response.Content.ReadAsStringAsync();
			
			if (response.IsSuccessStatusCode)
			{
				var jsonParser = new Json();
				if (jsonParser.Parse(responseText) == Error.Ok)
				{
					var result = jsonParser.Data.AsGodotDictionary();
					
					if (result.ContainsKey("messages"))
					{
						var messages = result["messages"].AsGodotArray();
						
						_chatHistories[friendId] = messages;
						EmitSignal(SignalName.ChatHistoryLoaded, friendId, messages);
						GD.Print($"[ChatManager] Loaded {messages.Count} messages from user {friendId}");
					}
				}
			}
		}
		catch (System.Exception e)
		{
			GD.PrintErr($"[ChatManager] Failed to load chat history: {e.Message}");
		}
	}
	
	// Get cached chat history
	public Array GetChatHistory(int friendId)
	{
		if (_chatHistories.ContainsKey(friendId))
		{
			return _chatHistories[friendId];
		}
		return new Array();
	}
	
	public void OnMessageReceived(Dictionary message)
	{
		Variant v = message["sender_id"];

		int senderId = v.VariantType switch
		{
			Variant.Type.Int => v.AsInt32(),
			Variant.Type.Float => (int)v.AsSingle(),
			Variant.Type.String => int.TryParse(v.AsString(), out var n) ? n : 0,
			_ => 0
		};

		AddMessageToHistory(senderId, message);
		EmitSignal(SignalName.MessageReceived, message);
	}
	
	private void AddMessageToHistory(int otherUserId, Dictionary message)
	{
		if (!_chatHistories.ContainsKey(otherUserId))
		{
			_chatHistories[otherUserId] = new Array();
		}
		
		_chatHistories[otherUserId].Add(message);
		
		if (_chatHistories[otherUserId].Count > 100)
		{
			_chatHistories[otherUserId].RemoveAt(0);
		}
	}
	
	public void ClearChatHistory(int friendId)
	{
		if (_chatHistories.ContainsKey(friendId))
		{
			_chatHistories[friendId].Clear();
		}
	}
	
	public void ClearAllChatHistories()
	{
		_chatHistories.Clear();
	}
	
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
		}
		return "Unknown error occurred";
	}
	
	public override void _ExitTree()
	{
		if (_accountManager != null)
		{
			_accountManager.Logout -= OnLogout;
		}
		_httpClient?.Dispose();
	}
}