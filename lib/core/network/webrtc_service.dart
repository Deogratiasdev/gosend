import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../models/transfer_request.dart';

class WebRTCService {
  final int signalingPort = 8080;
  HttpServer? _signalingServer;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  Function(Uint8List)? onDataReceived;
  Function(RTCDataChannelState)? onChannelStateChanged;
  Function(TransferRequest)? onTransferRequestReceived;
  Function(String, bool)? onTransferResponse;
  Function(String, String)? onControlMessage;

  final _iceServers = <String, dynamic>{
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ],
  };
  String? _currentPeerIp;

  Future<void> startSignalingServer() async {
    final router = Router()
      ..post('/offer', _handleOffer)
      ..post('/answer', _handleAnswer)
      ..post('/candidate', _handleCandidate);

    final handler = const Pipeline().addHandler(router.call);
    _signalingServer = await shelf_io.serve(handler, '0.0.0.0', signalingPort);
    debugPrint('Signaling server running on port $signalingPort');
  }

  Future<Response> _handleOffer(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    // Récupérer la vraie IP du peer (le Sender) depuis le contexte Shelf
    final connInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connInfo != null) {
      _currentPeerIp = connInfo.remoteAddress.address;
    } else {
      // Fallback qui ne devrait pas arriver
      _currentPeerIp = request.requestedUri.host;
    }

    await _createPeerConnection();
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    return Response.ok(
      jsonEncode({'sdp': answer.sdp, 'type': answer.type}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleAnswer(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    final connInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connInfo != null) {
      _currentPeerIp = connInfo.remoteAddress.address;
    } else {
      _currentPeerIp = request.requestedUri.host;
    }

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
    return Response.ok('OK');
  }

  Future<Response> _handleCandidate(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    final candidate = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );
    await _peerConnection?.addCandidate(candidate);
    return Response.ok('OK');
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentPeerIp != null && candidate.candidate != null) {
        _sendIceCandidate(candidate);
      }
    };

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('ICE connection state: $state');
    };
  }

  void _setupDataChannel() {
    _dataChannel?.onDataChannelState = (state) {
      onChannelStateChanged?.call(state);
    };
    _dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        onDataReceived?.call(message.binary);
      } else {
        _handleTextMessage(message.text);
      }
    };
  }

  void _handleTextMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'] as String?;

      if (type == 'transfer_request') {
        final request = TransferRequest.fromJson(
          data['payload'] as Map<String, dynamic>,
        );
        onTransferRequestReceived?.call(request);
      } else if (type == 'transfer_response') {
        final requestId = data['requestId'] as String;
        final accepted = data['accepted'] as bool;
        onTransferResponse?.call(requestId, accepted);
      } else if (type == 'control') {
        final requestId = data['requestId'] as String;
        final action = data['action'] as String;
        onControlMessage?.call(requestId, action);
      }
    } catch (e) {
      debugPrint('Error handling text message: $e');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_currentPeerIp == null) return;

    try {
      await http.post(
        Uri.parse('http://$_currentPeerIp:$signalingPort/candidate'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error sending ICE candidate: $e');
    }
  }

  Future<void> connectToPeer(String peerIp) async {
    _currentPeerIp = peerIp;
    await _createPeerConnection();

    final dataChannelDict = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;

    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      dataChannelDict,
    );
    _setupDataChannel();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Send offer to peer
    final response = await http.post(
      Uri.parse('http://$peerIp:$signalingPort/offer'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final answerData = jsonDecode(response.body);
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answerData['sdp'], answerData['type']),
      );
    }
    
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      final completer = Completer<void>();
      final originalCallback = onChannelStateChanged;
      onChannelStateChanged = (state) {
        if (originalCallback != null) originalCallback(state);
        debugPrint('DataChannel state: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen && !completer.isCompleted) {
          completer.complete();
        }
      };
      
      try {
        await completer.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw Exception("Délai de connexion dépassé (DataChannel non ouvert)");
      } finally {
        onChannelStateChanged = originalCallback;
      }
    }
  }

  void sendData(Uint8List data) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel?.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  void sendTransferRequest(TransferRequest request) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      final message = jsonEncode({
        'type': 'transfer_request',
        'payload': request.toJson(),
      });
      _dataChannel?.send(RTCDataChannelMessage(message));
    }
  }

  void sendTransferResponse(String requestId, bool accepted) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      final message = jsonEncode({
        'type': 'transfer_response',
        'requestId': requestId,
        'accepted': accepted,
      });
      _dataChannel?.send(RTCDataChannelMessage(message));
    }
  }

  void sendControlMessage(String requestId, String action) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      final message = jsonEncode({
        'type': 'control',
        'requestId': requestId,
        'action': action,
      });
      _dataChannel?.send(RTCDataChannelMessage(message));
    }
  }

  void dispose() {
    _dataChannel?.close();
    _peerConnection?.close();
    _signalingServer?.close();
  }
}
