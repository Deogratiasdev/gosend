import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class WebRTCService {
  final int signalingPort = 8080;
  HttpServer? _signalingServer;
  
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  Function(Uint8List)? onDataReceived;
  Function(RTCDataChannelState)? onChannelStateChanged;
  
  final _iceServers = <String, dynamic>{
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'}, // Fallback, not strictly needed for LAN
    ]
  };

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
    
    await _createPeerConnection();
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
    
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    
    return Response.ok(jsonEncode({'sdp': answer.sdp, 'type': answer.type}), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleAnswer(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
    return Response.ok('OK');
  }

  Future<Response> _handleCandidate(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);
    
    final candidate = RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
    await _peerConnection?.addCandidate(candidate);
    return Response.ok('OK');
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);
    
    _peerConnection!.onIceCandidate = (candidate) {
      // ICE candidates would be sent to the peer here via HTTP.
      // For simplicity in this demo, we assume the initial SDP exchange is enough for LAN,
      // but in a full implementation we'd POST to the peer's /candidate endpoint.
    };

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel();
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
        // Handle text messages if any
      }
    };
  }

  Future<void> connectToPeer(String peerIp) async {
    await _createPeerConnection();
    
    final dataChannelDict = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
      
    _dataChannel = await _peerConnection!.createDataChannel('fileTransfer', dataChannelDict);
    _setupDataChannel();
    
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    
    // Send offer to peer
    final response = await http.post(
      Uri.parse('http://$peerIp:$signalingPort/offer'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
    );
    
    if (response.statusCode == 200) {
      final answerData = jsonDecode(response.body);
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answerData['sdp'], answerData['type']),
      );
    }
  }

  void sendData(Uint8List data) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel?.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  void dispose() {
    _dataChannel?.close();
    _peerConnection?.close();
    _signalingServer?.close();
  }
}
