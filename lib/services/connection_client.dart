import 'dart:convert';
import 'package:http/http.dart' as http;

class ConnectionClient {
  static const int defaultPort = 8765;
  static const Duration timeout = Duration(seconds: 10);

  /// Envoie une demande de connexion au destinataire
  static Future<bool> sendConnectionRequest(
    String targetIP,
    String deviceName,
  ) async {
    try {
      final url = Uri.parse('http://$targetIP:$defaultPort/auth');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceName': deviceName}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'authorized';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Vérifie si un appareil est accessible (ping HTTP)
  static Future<bool> isDeviceReachable(String targetIP) async {
    try {
      final url = Uri.parse('http://$targetIP:$defaultPort/auth');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceName': 'ping'}),
          )
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200 || response.statusCode == 403;
    } catch (e) {
      return false;
    }
  }
}
