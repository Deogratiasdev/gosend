import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkService {
  static const int defaultPort = 8765;

  static Future<String?> getLocalIP() async {
    final info = NetworkInfo();
    String? ip = await info.getWifiIP();
    
    if (ip == null || ip == '0.0.0.0' || ip == '127.0.0.1') {
      try {
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              return addr.address;
            }
          }
        }
      } catch (e) {
        return null;
      }
    }
    return ip;
  }

  static bool isValidIP(String ip) => RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$').hasMatch(ip);

  static Future<void> openHotspotSettings() async {
    if (Platform.isAndroid) {
      await openAppSettings(); // Sur Android 13+, c'est le moyen le plus sûr d'arriver aux réglages
    }
  }
}
