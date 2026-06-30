import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'transfer_service.dart';

class FileClient {
  final Function(double)? onProgress;

  FileClient({this.onProgress});

  /// Demande l'autorisation au serveur avant d'envoyer
  Future<bool> authenticate(String ip, int port) async {
    try {
      final deviceName = await TransferService.instance.getDeviceName();
      final uri = Uri.parse('http://$ip:$port/auth');
      
      // On augmente le timeout car l'humain doit cliquer sur "Accepter"
      final response = await http.post(
        uri,
        body: jsonEncode({'deviceName': deviceName}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Envoie un seul fichier via HTTP Multipart
  Future<bool> sendFile(String ip, int port, File file) async {
    try {
      final uri = Uri.parse('http://$ip:$port/upload');
      final request = http.MultipartRequest('POST', uri);
      
      final multipartFile = await http.MultipartFile.fromPath(
        'file', 
        file.path,
        filename: path.basename(file.path),
      );
      
      request.files.add(multipartFile);
      final response = await request.send();
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Envoie une liste de fichiers un par un
  Future<bool> sendFiles(String ip, int port, List<File> files) async {
    // 1. Demande d'abord l'autorisation
    final isAuthorized = await authenticate(ip, port);
    if (!isAuthorized) return false;

    // 2. Envoi des fichiers
    try {
      int sentCount = 0;
      for (final file in files) {
        final success = await sendFile(ip, port, file);
        if (!success) return false;
        
        sentCount++;
        if (onProgress != null) {
          onProgress!(sentCount / files.length);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
