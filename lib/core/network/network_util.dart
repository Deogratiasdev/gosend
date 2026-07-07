import 'dart:io';

/// Utilitaires réseau partagés pour la découverte multi-interfaces.
/// Fonctionne en dart:io pur (Windows / Linux / macOS / Android),
/// aucune dépendance externe supplémentaire.
class NetworkUtil {
  NetworkUtil._();

  /// Préfixes d'interface à ignorer : cellulaire, tunnel, loopback, virtuel.
  /// IMPORTANT : on ne met PAS 'wlan', 'ap', 'wl' ici car ce sont les
  /// interfaces Wi-Fi / hotspot qui nous intéressent.
  static const _skipPrefixes = [
    'rmnet', 'ccmni', 'pdp', 'tun', 'ppp', 'usb', 'ip6', 'sit', 'lo',
    'dummy', 'veth', 'br-', 'docker', 'virbr', 'vmnet', 'tap',
  ];

  /// Vrai si [ip] est une adresse IPv4 privée (RFC1918).
  static bool isPrivateV4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// Vrai si le nom d'interface est cellulaire / virtuel / loopback.
  /// Ne filtre PAS les interfaces Wi-Fi / hotspot (wlan0, ap0, etc.).
  static bool isMobileOrVirtual(String name) {
    final lower = name.toLowerCase();
    if (lower == 'lo' || lower == 'loopback') return true;
    for (final prefix in _skipPrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Énumère toutes les interfaces IPv4 utilisables (non loopback, non
  /// cellulaire, non virtuelle).
  static Future<List<({String name, InternetAddress address})>>
  listUsableIPv4Interfaces() async {
    final result = <({String name, InternetAddress address})>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (isMobileOrVirtual(iface.name)) continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            result.add((name: iface.name, address: addr));
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Retourne la première IPv4 privée utilisable.
  /// Fallback quand [getWifiIP()] échoue (hotspot Android = STA éteinte).
  /// Priorité absolue : interface hotspot (IP en .1 sur ap0/wlan1)
  /// puis interface WiFi classique, puis toute IP privée.
  static Future<String> detectLocalIp() async {
    final ifaces = await listUsableIPv4Interfaces();

    // Priorité 1 : interface hotspot (IP se terminant par .1)
    // C'est l'IP de passerelle du hotspot, celle que les clients peuvent joindre.
    // Critère : interface nommée ap* / wlan1* / softap* avec IP en .1
    for (final i in ifaces) {
      final lower = i.name.toLowerCase();
      final isAp = lower.startsWith('ap') ||
          lower.startsWith('softap') ||
          lower == 'wlan1' ||
          lower.contains('hotspot');
      if (isAp && isPrivateV4(i.address.address)) {
        return i.address.address;
      }
    }

    // Priorité 2 : n'importe quelle IP en .1 sur réseau privé
    // (couvre le cas où l'interface hotspot a un nom non standard)
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) {
        final parts = i.address.address.split('.');
        if (parts.length == 4 && parts[3] == '1') {
          return i.address.address;
        }
      }
    }

    // Priorité 3 : interface WiFi classique (wlan0)
    for (final i in ifaces) {
      final lower = i.name.toLowerCase();
      if ((lower.startsWith('wlan') || lower.startsWith('wl')) &&
          isPrivateV4(i.address.address)) {
        return i.address.address;
      }
    }

    // Priorité 4 : n'importe quelle IP privée
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) return i.address.address;
    }
    return 'Non disponible';
  }

  /// Retourne TOUTES les IPv4 privées de l'appareil.
  /// Utilisé pour inclure toutes les IP dans les requêtes de transfert,
  /// afin que le récepteur puisse choisir celle qu'il peut joindre.
  static Future<List<String>> allLocalIps() async {
    final ifaces = await listUsableIPv4Interfaces();
    final ips = <String>[];
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) {
        ips.add(i.address.address);
      }
    }
    return ips;
  }

  /// Directed broadcast pour un /24 : 192.168.43.42 → 192.168.43.255.
  static String directedBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return '255.255.255.255';
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  /// Ensemble des directed broadcasts sur chaque interface utilisable.
  static Future<Set<String>> directedBroadcastTargets() async {
    final targets = <String>{};
    final ifaces = await listUsableIPv4Interfaces();
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) {
        targets.add(directedBroadcast(i.address.address));
      }
    }
    return targets;
  }

  /// Devine la passerelle par défaut (hôte hotspot côté client).
  /// Heuristique : x.y.z.1 du sous-réseau local.
  static Future<String?> guessGateway() async {
    final ifaces = await listUsableIPv4Interfaces();
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) {
        final parts = i.address.address.split('.');
        if (parts.length == 4) {
          return '${parts[0]}.${parts[1]}.${parts[2]}.1';
        }
      }
    }
    return null;
  }

  /// Liste les 254 hôtes d'un /24 autour de [localIp], en excluant soi-même.
  static List<String> subnetHosts(String localIp) {
    final parts = localIp.split('.');
    if (parts.length != 4) return [];
    final out = <String>[];
    for (int i = 1; i <= 254; i++) {
      if (i.toString() == parts[3]) continue;
      out.add('${parts[0]}.${parts[1]}.${parts[2]}.$i');
    }
    return out;
  }

  // ─────────────── LECTURE TABLE ARP ───────────────

  /// Lit la table ARP pour trouver les IP des clients connectés.
  /// Fonctionne sur Android/Linux (/proc/net/arp) et Windows (arp -a).
  /// Retourne la liste des IP trouvées dans la table ARP qui sont dans
  /// un sous-réseau privé (donc des peers locaux).
  static Future<List<String>> readArpTable() async {
    final ips = <String>{};

    if (Platform.isLinux || Platform.isAndroid) {
      // Android / Linux : lecture directe de /proc/net/arp
      try {
        final file = File('/proc/net/arp');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          // Format : IP address  HW type  Flags  HW address  Mask  Device
          // Skip la première ligne (header)
          for (var i = 1; i < lines.length; i++) {
            final parts = lines[i].trim().split(RegExp(r'\s+'));
            if (parts.isNotEmpty) {
              final ip = parts[0];
              if (isPrivateV4(ip)) ips.add(ip);
            }
          }
        }
      } catch (_) {}
    }

    if (Platform.isWindows) {
      // Windows : parse la sortie de "arp -a"
      try {
        final result = await Process.run('arp', ['-a']);
        final lines = (result.stdout as String).split('\n');
        final ipRegex = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})');
        for (final line in lines) {
          final match = ipRegex.firstMatch(line);
          if (match != null) {
            final ip = match.group(1)!;
            if (isPrivateV4(ip)) ips.add(ip);
          }
        }
      } catch (_) {}
    }

    if (Platform.isMacOS) {
      // macOS : parse la sortie de "arp -a"
      try {
        final result = await Process.run('arp', ['-a']);
        final lines = (result.stdout as String).split('\n');
        // Format macOS : hostname (ip) at mac on iface
        final ipRegex = RegExp(r'\((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\)');
        for (final line in lines) {
          final match = ipRegex.firstMatch(line);
          if (match != null) {
            final ip = match.group(1)!;
            if (isPrivateV4(ip)) ips.add(ip);
          }
        }
      } catch (_) {}
    }

    return ips.toList();
  }

  /// Détecte si l'appareil est actuellement un hôte hotspot.
  /// Fonctionne sur Android (ap0/wlan0), Windows (Local Area Connection*),
  /// macOS et Linux.
  /// Heuristique : une interface avec une IP privée en .1 (passerelle),
  /// SSI il y a au moins une autre interface avec une IP privée différente
  /// (ex: 192.168.x.y) -> on est dual-homed (WiFi + hotspot).
  /// Si une seule interface en .1, on est probablement juste client
  /// (ex: 192.168.1.1 = routeur) -> faux positif évité.
  static Future<bool> isHotspotHost() async {
    final ifaces = await listUsableIPv4Interfaces();
    final privateIps = <String>[];
    for (final i in ifaces) {
      if (isPrivateV4(i.address.address)) {
        privateIps.add(i.address.address);
      }
    }
    // Il faut au moins 2 IP privées pour être dual-homed
    if (privateIps.length < 2) return false;
    // Au moins une IP doit se terminer par .1 (passerelle hotspot)
    for (final ip in privateIps) {
      final parts = ip.split('.');
      if (parts.length == 4 && parts[3] == '1') {
        return true;
      }
    }
    return false;
  }
}
