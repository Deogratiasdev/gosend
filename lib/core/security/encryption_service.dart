import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple XOR-based encryption for broadcast messages.
/// Provides obfuscation to prevent casual network sniffing.
/// Key is stored locally and used for both encrypt/decrypt.
class EncryptionService {
  static const String _keyStorageKey = 'broadcast_encryption_key';

  /// Singleton instance
  static EncryptionService? _instance;

  String _encryptionKey = '';
  bool _initialized = false;

  EncryptionService._();

  /// Get singleton instance
  static EncryptionService get instance {
    _instance ??= EncryptionService._();
    return _instance!;
  }

  /// Initialize from SharedPreferences (call once at app startup)
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _encryptionKey = prefs.getString(_keyStorageKey) ?? '';
      _initialized = true;
      debugPrint('🔐 EncryptionService initialisé (clé: ${_encryptionKey.isNotEmpty ? "définie" : "aucune"})');
    } catch (e) {
      debugPrint('❌ Erreur init EncryptionService: $e');
    }
  }

  /// Save key to SharedPreferences
  Future<void> _saveKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_encryptionKey.isEmpty) {
        await prefs.remove(_keyStorageKey);
      } else {
        await prefs.setString(_keyStorageKey, _encryptionKey);
      }
    } catch (e) {
      debugPrint('❌ Erreur sauvegarde clé: $e');
    }
  }

  String get encryptionKey => _encryptionKey;
  bool get isKeySet => _encryptionKey.isNotEmpty;

  /// Generates a random 32-character key
  Future<String> generateKey() async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*';
    final random = Random.secure();
    _encryptionKey = List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
    await _saveKey();
    debugPrint('🔐 Nouvelle clé de chiffrement générée');
    return _encryptionKey;
  }

  /// Set the encryption key manually
  Future<void> setKey(String key) async {
    if (key.isEmpty) {
      debugPrint('⚠️ Clé vide, chiffrement désactivé');
      _encryptionKey = '';
    } else {
      _encryptionKey = key;
      debugPrint('🔐 Clé de chiffrement définie');
    }
    await _saveKey();
  }

  /// Clear the key (disable encryption)
  Future<void> clearKey() async {
    _encryptionKey = '';
    await _saveKey();
    debugPrint('🔓 Clé de chiffrement effacée');
  }

  /// Encrypts text using XOR with the key
  /// Returns Base64 encoded result for safe transmission
  String? encrypt(String plainText) {
    if (_encryptionKey.isEmpty) {
      debugPrint('⚠️ Pas de clé définie, message envoyé en clair');
      return plainText;
    }

    try {
      final keyBytes = utf8.encode(_encryptionKey);
      final textBytes = utf8.encode(plainText);
      final encrypted = List<int>.generate(textBytes.length, (i) => textBytes[i] ^ keyBytes[i % keyBytes.length]);

      return base64Encode(encrypted);
    } catch (e) {
      debugPrint('❌ Erreur chiffrement: $e');
      return plainText;
    }
  }

  /// Decrypts Base64 encoded text using XOR with the key
  String? decrypt(String encryptedText) {
    if (_encryptionKey.isEmpty) {
      debugPrint('⚠️ Pas de clé définie');
      return encryptedText;
    }

    try {
      final keyBytes = utf8.encode(_encryptionKey);
      final encryptedBytes = base64Decode(encryptedText);
      final decrypted = List<int>.generate(encryptedBytes.length, (i) => encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);

      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('❌ Erreur déchiffrement: $e');
      // Return as-is if decryption fails (might be plain text from old client)
      return encryptedText;
    }
  }

  /// Check if a message appears to be encrypted (Base64 pattern)
  bool isEncrypted(String message) {
    if (message.isEmpty) return false;
    // Simple heuristic: encrypted messages are longer Base64 strings
    // and don't contain common text patterns
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]+=*$');
    return base64Pattern.hasMatch(message) && message.length > 20;
  }

  /// Try to decrypt, fall back to plain text if not encrypted
  String safeDecrypt(String message) {
    if (isEncrypted(message)) {
      final decrypted = decrypt(message);
      if (decrypted != null && decrypted != message) {
        return decrypted;
      }
    }
    return message;
  }
}
