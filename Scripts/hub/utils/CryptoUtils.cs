using Godot;
using System;
using System.Security.Cryptography;
using System.Text;

public static class CryptoUtils
{
	private const string MachineKeyPath = "user://machine.key";
	private const int KeyBytes = 32;   // AES-256
	private const int NonceBytes = 12; // GCM standard nonce
	private const int TagBytes = 16;   // 128-bit authentication tag

	public static byte[] GetOrCreateMachineKey()
	{
		try
		{
			if (FileAccess.FileExists(MachineKeyPath))
			{
				using var f = FileAccess.Open(MachineKeyPath, FileAccess.ModeFlags.Read);
				if (f != null)
				{
					var b64 = f.GetAsText().Trim();
					var key = Convert.FromBase64String(b64);
					if (key.Length == KeyBytes) return key;
				}
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[CryptoUtils] Failed to load machine key: {e.Message}");
		}

		// Generate a fresh cryptographically random machine key.
		var newKey = System.Security.Cryptography.RandomNumberGenerator.GetBytes(KeyBytes);
		try
		{
			using var fw = FileAccess.Open(MachineKeyPath, FileAccess.ModeFlags.Write);
			if (fw != null) fw.StoreString(Convert.ToBase64String(newKey));
			GD.Print("[CryptoUtils] New machine key generated and saved");
		}
		catch (Exception e)
		{
			GD.PrintErr($"[CryptoUtils] Failed to save machine key: {e.Message}");
		}

		return newKey;
	}

	public static string Encrypt(string plaintext)
	{
		if (string.IsNullOrEmpty(plaintext)) return "";

		var key = GetOrCreateMachineKey();
		var nonce = System.Security.Cryptography.RandomNumberGenerator.GetBytes(NonceBytes);
		var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
		var ciphertext = new byte[plaintextBytes.Length];
		var tag = new byte[TagBytes];

		using var aes = new AesGcm(key, TagBytes);
		aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

		return $"{Convert.ToBase64String(nonce)}:{Convert.ToBase64String(ciphertext)}:{Convert.ToBase64String(tag)}";
	}

	public static string Decrypt(string encrypted)
	{
		try
		{
			if (string.IsNullOrEmpty(encrypted)) return "";

			var parts = encrypted.Split(':');
			if (parts.Length != 3) return "";

			var key = GetOrCreateMachineKey();
			var nonce = Convert.FromBase64String(parts[0]);
			var ciphertext = Convert.FromBase64String(parts[1]);
			var tag = Convert.FromBase64String(parts[2]);
			var plaintext = new byte[ciphertext.Length];

			using var aes = new AesGcm(key, TagBytes);
			aes.Decrypt(nonce, ciphertext, tag, plaintext);

			return Encoding.UTF8.GetString(plaintext);
		}
		catch
		{
			// Decryption failure = tampered data, wrong machine, or corrupt file.
			return "";
		}
	}
	public static void DeleteMachineKey()
	{
		try
		{
			if (FileAccess.FileExists(MachineKeyPath))
			{
				DirAccess.RemoveAbsolute(MachineKeyPath);
				GD.Print("[CryptoUtils] Machine key deleted");
			}
		}
		catch (Exception e)
		{
			GD.PrintErr($"[CryptoUtils] Failed to delete machine key: {e.Message}");
		}
	}
}
