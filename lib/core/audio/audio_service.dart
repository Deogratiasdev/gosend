import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Audio service for playing notification and UI sounds.
///
/// Offline-first : aucun fallback réseau (pas de requête internet sur
/// hotspot). Si l'asset manque (non déclaré dans pubspec), on reste
/// silencieux au lieu de spammer les logs.
class AudioService {
  static AudioService? _instance;
  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;
  bool _assetsMissingLogged = false;

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

  Future<void> _playAsset(String asset, double volume) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // Asset absent (ex. sounds/ non déclaré) : silence, un seul log.
      if (!_assetsMissingLogged) {
        _assetsMissingLogged = true;
        debugPrint('🔇 Sons indisponibles ($asset manquant), audio désactivé');
        _enabled = false;
      }
    }
  }

  /// Play sound when files are added to the list
  Future<void> playFileAdded() => _playAsset('sounds/file_added.wav', 0.5);

  /// Play sound when files are received successfully
  Future<void> playFileReceived() =>
      _playAsset('sounds/file_received.wav', 0.6);

  /// Play a short notification beep
  Future<void> playNotification() =>
      _playAsset('sounds/notification.wav', 0.4);

  /// Play transfer start sound
  Future<void> playTransferStart() =>
      _playAsset('sounds/transfer_start.wav', 0.5);

  void dispose() {
    _player.dispose();
  }
}
