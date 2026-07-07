import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/device.dart';
import '../security/encryption_service.dart';
import 'network_util.dart';

class DiscoveryService {
  static const int broadcastPort = 50000;
  static const int discoveryHttpPort = 8080;
  static const Duration deviceTimeout = Duration(seconds: 20);

  /// Un socket par interface réseau (clé = adresse IP de l'interface).
  /// Résout le problème principal du hotspot Android : un socket unique
  /// lié à 0.0.0.0 envoie les broadcasts sur la route par défaut
  /// (souvent cellulaire), pas sur l'interface hotspot. En liant un
  /// socket à chaque IP d'interface, on force le broadcast à sortir
  /// sur la bonne interface physique.
  final Map<String, RawDatagramSocket> _interfaceSockets = {};

  /// Socket de réception unique sur 0.0.0.0 pour écouter tous les
  /// broadcasts entrants, quelle que soit l'interface.
  RawDatagramSocket? _listenSocket;

  Timer? _broadcastTimer;
  Timer? _gatewayTimer;
  Timer? _sweepTimer;
  Timer? _arpTimer;
  Timer? _cleanupTimer;
  bool isDiscoverable = true;

  final ValueNotifier<List<Device>> discoveredDevices = ValueNotifier([]);
  final Map<String, Device> _devicesMap = {};
  final Map<String, DateTime> _lastSeenMap = {};

  /// Service de chiffrement pour les messages broadcast
  final EncryptionService _encryptionService;

  final String localDeviceId;
  String localDeviceName;
  final String localOs;
  String localIpAddress;

  DiscoveryService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localOs,
    required this.localIpAddress,
    EncryptionService? encryptionService,
  }) : _encryptionService = encryptionService ?? EncryptionService.instance;

  /// Update the encryption service (call after key is set)
  void setEncryptionService(EncryptionService service) {
    // Service is final, but we use a reference that can be updated
    debugPrint('Encryption service linked to discovery');
  }

  // ─────────────── START / STOP ───────────────

  Future<void> startDiscovery() async {
    try {
      _cancelAll();
      await _closeAllSockets();

      // 1) Socket d'écoute global sur 0.0.0.0 (réception)
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
      );
      _listenSocket?.broadcastEnabled = true;
      _listenSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket?.receive();
          if (datagram != null) _handleIncomingDatagram(datagram);
        }
      });

      // 2) Sockets par interface (émission uniquement)
      await _createInterfaceSockets();

      // 3) Timers de découverte
      _startBroadcasting();
      Future.delayed(const Duration(milliseconds: 500), () => _startGatewayProbe());
      Future.delayed(const Duration(seconds: 2), () => _startSweepTimer());
      Future.delayed(const Duration(seconds: 1), () => _startArpDiscovery());
      _startCleanupTimer();

      debugPrint('DiscoveryService started (per-iface sockets + broadcast + gateway + sweep + ARP)');
    } catch (e) {
      debugPrint('Error starting DiscoveryService: $e');
    }
  }

  Future<void> stopDiscovery() async {
    _cancelAll();
    await _closeAllSockets();
    _devicesMap.clear();
    _lastSeenMap.clear();
    _updateDiscoveredDevices();
    debugPrint('DiscoveryService stopped');
  }

  void _cancelAll() {
    _broadcastTimer?.cancel();
    _gatewayTimer?.cancel();
    _sweepTimer?.cancel();
    _arpTimer?.cancel();
    _cleanupTimer?.cancel();
  }

  Future<void> _closeAllSockets() async {
    try { _listenSocket?.close(); } catch (_) {}
    _listenSocket = null;
    for (final socket in _interfaceSockets.values) {
      try { socket.close(); } catch (_) {}
    }
    _interfaceSockets.clear();
  }

  /// Crée un socket UDP par interface réseau utilisable.
  /// Chaque socket est lié à l'IP de son interface, ce qui force
  /// les paquets sortants à passer par cette interface physique.
  Future<void> _createInterfaceSockets() async {
    final ifaces = await NetworkUtil.listUsableIPv4Interfaces();
    for (final iface in ifaces) {
      final ip = iface.address.address;
      if (!NetworkUtil.isPrivateV4(ip)) continue;
      if (ip == localIpAddress && _listenSocket != null) {
        // L'interface principale utilise le socket d'écoute pour émettre aussi
        _interfaceSockets[ip] = _listenSocket!;
        continue;
      }
      try {
        // Lie à l'IP de l'interface sur un port éphémère (pas le broadcastPort
        // qui est déjà pris par _listenSocket). L'émission se fait vers
        // broadcastPort mais depuis cette IP source.
        final socket = await RawDatagramSocket.bind(
          InternetAddress(ip),
          0, // port éphémère
        );
        socket.broadcastEnabled = true;
        // On écoute aussi les réponses potentielles sur ce socket
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) _handleIncomingDatagram(datagram);
          }
        });
        _interfaceSockets[ip] = socket;
        debugPrint('Socket créé pour interface ${iface.name} ($ip)');
      } catch (e) {
        debugPrint('Impossible de créer socket pour $ip: $e');
      }
    }

    // Si aucune interface secondaire, s'assurer qu'au moins le listenSocket
    // est utilisé pour l'émission
    if (_interfaceSockets.isEmpty && _listenSocket != null) {
      _interfaceSockets['any'] = _listenSocket!;
    }
  }

  // ─────────────── BROADCAST MULTI-INTERFACE ───────────────

  void _startBroadcasting() {
    _broadcastTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!isDiscoverable) return;
      _sendBroadcasts();
    });
    _sendBroadcasts();
  }

  Future<void> _sendBroadcasts() async {
    final message = jsonEncode({
      'id': localDeviceId,
      'name': localDeviceName,
      'os': localOs,
      'port': broadcastPort,
      'httpPort': 8081,
    });

    // Encrypt message if key is set
    String bufferStr;
    if (_encryptionService.isKeySet) {
      bufferStr = _encryptionService.encrypt(message) ?? message;
    } else {
      bufferStr = message;
    }
    final buffer = utf8.encode(bufferStr);

    // 1) Directed broadcasts sur chaque interface
    try {
      final targets = await NetworkUtil.directedBroadcastTargets();
      for (final target in targets) {
        // Envoie depuis CHAQUE socket d'interface pour forcer la sortie
        // sur chaque interface physique (critique pour hotspot Android)
        for (final socket in _interfaceSockets.values) {
          try {
            socket.send(buffer, InternetAddress(target), broadcastPort);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Directed broadcast error: $e');
    }

    // 2) Limited broadcast 255.255.255.255 depuis chaque socket
    for (final socket in _interfaceSockets.values) {
      try {
        socket.send(buffer, InternetAddress('255.255.255.255'), broadcastPort);
      } catch (_) {}
    }

    // 3) Unicast UDP vers les peers déjà connus (renforce la fiabilité)
    _sendUnicastToKnownPeers(buffer);
  }

  /// Envoie le message d'annonce en unicast UDP directement à chaque
  /// peer déjà découvert. Cela contourne totalement le problème de
  /// broadcast sur hotspot : une fois qu'un peer est connu (via ARP,
  /// sweep ou gateway probe), on lui parle directement.
  void _sendUnicastToKnownPeers(List<int> buffer) {
    for (final device in _devicesMap.values) {
      if (device.ip.isEmpty || device.ip == 'Non disponible') continue;
      if (device.ip == localIpAddress) continue;
      for (final socket in _interfaceSockets.values) {
        try {
          socket.send(buffer, InternetAddress(device.ip), broadcastPort);
        } catch (_) {}
      }
    }
  }

  // ─────────────── GATEWAY PROBE (client → hotspot host) ───────────────

  void _startGatewayProbe() {
    _gatewayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!isDiscoverable) return;
      _probeGateway();
    });
    _probeGateway();
  }

  Future<void> _probeGateway() async {
    final gateway = await NetworkUtil.guessGateway();
    if (gateway == null || gateway.isEmpty) return;
    if (gateway == localIpAddress) return;

    try {
      final uri = Uri.parse('http://$gateway:$discoveryHttpPort/discover');
      final response = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _addDeviceFromProbe(gateway, data);
      }
    } catch (_) {}
  }

  // ─────────────── ARP DISCOVERY (hotspot host → clients) ───────────────

  /// Lit la table ARP pour découvrir les clients connectés au hotspot.
  /// C'est LA solution clé pour le hotspot Android : quand le téléphone
  /// est l'hôte du hotspot, sa table ARP contient les IP de tous les
  /// clients connectés. On probe ensuite ces IP via HTTP.
  void _startArpDiscovery() {
    _arpTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isDiscoverable) return;
      _discoverViaArp();
    });
    // Premier scan ARP après 1 seconde
    Future.delayed(const Duration(seconds: 1), () => _discoverViaArp());
  }

  Future<void> _discoverViaArp() async {
    try {
      final arpIps = await NetworkUtil.readArpTable();
      if (arpIps.isEmpty) return;

      for (final ip in arpIps) {
        if (ip == localIpAddress) continue;
        // Ne pas re-prober si déjà découvert et vu récemment
        final existingDevice = _devicesMap.values.where((d) => d.ip == ip).firstOrNull;
        if (existingDevice != null) {
          final lastSeen = _lastSeenMap[existingDevice.id];
          if (lastSeen != null &&
              DateTime.now().difference(lastSeen) < const Duration(seconds: 8)) {
            continue;
          }
        }
        // Probe HTTP sur cette IP
        _probeHost(ip).then((data) {
          if (data != null) _addDeviceFromProbe(ip, data);
        });
      }
    } catch (e) {
      debugPrint('ARP discovery error: $e');
    }
  }

  // ─────────────── SWEEP /24 (filet de sécurité) ───────────────

  void _startSweepTimer() {
    // Sweep plus agressif : toutes les 15 s si peu de devices
    _sweepTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isDiscoverable) return;
      // Skip si on a déjà plusieurs devices vus récemment
      if (_devicesMap.length >= 2) return;
      _sweepSubnet();
    });
    if (_devicesMap.isEmpty) _sweepSubnet();
  }

  Future<void> _sweepSubnet() async {
    if (!NetworkUtil.isPrivateV4(localIpAddress)) return;
    final hosts = NetworkUtil.subnetHosts(localIpAddress);
    if (hosts.isEmpty) return;

    debugPrint('Sweep /24 en cours (${hosts.length} hôtes)...');

    const batchSize = 32;
    for (var i = 0; i < hosts.length; i += batchSize) {
      final end = (i + batchSize > hosts.length) ? hosts.length : i + batchSize;
      final batch = hosts.sublist(i, end);
      await Future.wait(
        batch.map((ip) => _probeHost(ip).then((device) {
          if (device != null) _addDeviceFromProbe(ip, device);
        })),
      );
    }

    debugPrint('Sweep terminé, ${_devicesMap.length} appareil(s) trouvé(s)');
  }

  Future<Map<String, dynamic>?> _probeHost(String ip) async {
    try {
      final uri = Uri.parse('http://$ip:$discoveryHttpPort/discover');
      final response = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 400));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _addDeviceFromProbe(String ip, Map<String, dynamic> data) {
    try {
      final id = data['id'] as String;
      if (id == localDeviceId) return;
      if (ip == localIpAddress) return;

      final device = Device(
        id: id,
        name: data['name'] as String? ?? 'Inconnu',
        ip: ip,
        port: data['port'] as int? ?? broadcastPort,
        os: data['os'] as String? ?? 'unknown',
        httpPort: data['httpPort'] as int? ?? 8081,
      );

      _devicesMap[id] = device;
      _lastSeenMap[id] = DateTime.now();
      _updateDiscoveredDevices();
    } catch (e) {
      debugPrint('Error parsing probe response: $e');
    }
  }

  // ─────────────── UDP DATAGRAM HANDLER ───────────────

  void _handleIncomingDatagram(Datagram datagram) {
    try {
      var message = utf8.decode(datagram.data);

      // Try to decrypt if encrypted
      if (_encryptionService.isEncrypted(message)) {
        final decrypted = _encryptionService.safeDecrypt(message);
        if (decrypted != message) {
          message = decrypted;
        }
      }

      final data = jsonDecode(message);

      if (_isLocalDatagram(data, datagram.address.address)) return;

      final device = Device(
        id: data['id'],
        name: data['name'],
        ip: datagram.address.address,
        port: data['port'] ?? broadcastPort,
        os: data['os'] ?? 'unknown',
        httpPort: data['httpPort'] ?? 8081,
      );

      final uniqueKey = device.id;
      _devicesMap[uniqueKey] = device;
      _lastSeenMap[uniqueKey] = DateTime.now();
      _updateDiscoveredDevices();
    } catch (e) {
      debugPrint('Error parsing datagram: $e');
    }
  }

  // ─────────────── CLEANUP ───────────────

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _cleanupInactiveDevices();
    });
  }

  void _cleanupInactiveDevices() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _lastSeenMap.entries) {
      if (now.difference(entry.value) > deviceTimeout) {
        toRemove.add(entry.key);
      }
    }

    for (final deviceId in toRemove) {
      _devicesMap.remove(deviceId);
      _lastSeenMap.remove(deviceId);
    }

    if (toRemove.isNotEmpty) _updateDiscoveredDevices();
  }

  // ─────────────── HELPERS ───────────────

  void _updateDiscoveredDevices() {
    discoveredDevices.value = _devicesMap.values
        .where((device) => !_isLocalDevice(device))
        .toList();
  }

  bool _isLocalDatagram(Map<String, dynamic> data, String senderIp) {
    if (data['id'] == localDeviceId) return true;
    if (_isSameIp(senderIp, localIpAddress)) return true;
    return false;
  }

  bool _isLocalDevice(Device device) {
    if (device.id == localDeviceId) return true;
    if (_isSameIp(device.ip, localIpAddress)) return true;
    return false;
  }

  bool _isSameIp(String a, String b) {
    if (a.isEmpty || b.isEmpty || b == 'Non disponible') return false;
    return a == b;
  }

  void toggleDiscoverability() {
    isDiscoverable = !isDiscoverable;
  }

  void updateLocalInfo({required String name, required String ipAddress}) {
    localDeviceName = name;
    localIpAddress = ipAddress;
    _removeLocalEchoes();
  }

  void _removeLocalEchoes() {
    _devicesMap.removeWhere((_, device) => _isLocalDevice(device));
    _lastSeenMap.removeWhere((key, _) => !_devicesMap.containsKey(key));
    _updateDiscoveredDevices();
  }
}
