import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Audio service for playing notification and UI sounds.
class AudioService {
  static AudioService? _instance;
  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;

  AudioService._();

  static AudioService get instance {
    _instance ??= AudioService._();
    return _instance!;
  }

  bool get isEnabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
    debugPrint('🔊 Audio ${_enabled ? "activé" : "désactivé"}');
  }

  /// Play sound when files are added to the list
  Future<void> playFileAdded() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      // Use a pleasant notification sound - system default
      await _player.play(
        AssetSource('sounds/file_added.mp3'),
        volume: 0.5,
      );
    } catch (e) {
      // Fallback: try to play a tone if asset not found
      debugPrint('⚠️ Son ajout fichier non disponible: $e');
      // Play a simple system beep using TTS as fallback on mobile
      try {
        await _player.play(
          UrlSource('https://actions.google.com/sounds/v1/alerts/beep_short.ogg'),
          volume: 0.3,
        );
      } catch (_) {}
    }
  }

  /// Play sound when files are received successfully
  Future<void> playFileReceived() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/file_received.mp3'),
        volume: 0.6,
      );
    } catch (e) {
      debugPrint('⚠️ Son réception fichier non disponible: $e');
      // Fallback notification sound
      try {
        await _player.play(
          UrlSource('https://actions.google.com/sounds/v1/alerts/complete.ogg'),
          volume: 0.4,
        );
      } catch (_) {}
    }
  }

  /// Play a short notification beep
  Future<void> playNotification() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(
        UrlSource('https://actions.google.com/sounds/v1/alerts/beep.ogg'),
        volume: 0.4,
      );
    } catch (e) {
      debugPrint('⚠️ Son notification non disponible: $e');
    }
  }

  /// Play transfer start sound
  Future<void> playTransferStart() async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/transfer_start.mp3'),
        volume: 0.5,
      );
    } catch (e) {
      debugPrint('⚠️ Son début transfert non disponible: $e');
      try {
        await _player.play(
          UrlSource('https://actions.google.com/sounds/v1/cartoon/cartoon_boing.ogg'),
          volume: 0.3,
        );
      } catch (_) {}
    }
  }

  void dispose() {
    _player.dispose();
  }
}
