import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf_multipart/multipart.dart';
import 'transfer_service.dart';

class FileServer {
  HttpServer? _server;
  final int port;
  final Function(String)? onFileReceived;
  final ConnectedDevice Function(String deviceName, String ip) onAuthRequest;

  FileServer({required this.port, this.onFileReceived, required this.onAuthRequest});

  Future<bool> start() async {
    final router = Router();

    // Route d'autorisation : Attend que l'utilisateur distant clique sur "Accepter"
    router.post('/auth', (Request request) async {
      try {
        final payload = jsonDecode(await request.readAsString());
        final deviceName = payload['deviceName'] ?? 'Appareil Inconnu';
        final conn = request.context['shelf.io.connection_info'] as HttpConnectionInfo;
        final ip = conn.remoteAddress.address;

        final device = onAuthRequest(deviceName, ip);
        
        // Attente de l'autorisation via le Completer (timeout 60s)
        final authorized = await device.authCompleter!.future.timeout(
          const Duration(seconds: 60), 
          onTimeout: () => false
        );

        return authorized 
          ? Response.ok(jsonEncode({'status': 'authorized'}))
          : Response.forbidden(jsonEncode({'status': 'denied'}));
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    // Route d'upload
    router.post('/upload', (Request request) async {
      final conn = request.context['shelf.io.connection_info'] as HttpConnectionInfo;
      if (!TransferService.instance.isDeviceAuthorized(conn.remoteAddress.address)) {
        return Response.forbidden('Non autorisé');
      }
      return await _handleMultipartUpload(request);
    });

    try {
      final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      _server?.idleTimeout = const Duration(minutes: 15);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handleMultipartUpload(Request request) async {
    if (!request.isMultipart) return Response.badRequest(body: 'Not multipart');
    try {
      final saveDir = await _getSaveDirectory();
      await for (final formData in request.multipartFormData) {
        if (formData.filename != null) {
          String fileName = formData.filename!;
          String filePath = path.join(saveDir.path, fileName);
          if (await File(filePath).exists()) {
            fileName = "${path.basenameWithoutExtension(fileName)}_${DateTime.now().millisecondsSinceEpoch}${path.extension(fileName)}";
            filePath = path.join(saveDir.path, fileName);
          }
          final file = File(filePath);
          final sink = file.openWrite();
          await formData.part.forEach((chunk) => sink.add(chunk));
          await sink.close();
          onFileReceived?.call(fileName);
        }
      }
      return Response.ok('OK');
    } catch (e) {
      return Response.internalServerError(body: '$e');
    }
  }

  Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) return Directory('/storage/emulated/0/Download/GoSend')..createSync(recursive: true);
    final downloads = await getDownloadsDirectory();
    return Directory(path.join(downloads!.path, 'GoSend'))..createSync(recursive: true);
  }
}
