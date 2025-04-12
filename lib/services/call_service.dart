// ✅ 전체 오류 해결 및 자동 녹음 기능 포함된 간결한 CallService + autoConnect 추가
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'auto_transcription_service.dart';

class CallService with ChangeNotifier {
  final _localRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final _remoteRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final _incomingCallController = StreamController<Map<String, String>>.broadcast();
  final _onlineUsersController = StreamController<List<Map<String, dynamic>>>.broadcast();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _isInCall = false;
  String _roomId = '';
  bool _isOffer = false;
  String? _conversationId;
  bool _isConnectionFailed = false;
  String? _errorMessage;

  final AutoTranscriptionService _autoTranscriptionService = AutoTranscriptionService();

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  bool get isConnectionFailed => _isConnectionFailed;
  String? get errorMessage => _errorMessage;

  Stream<RTCVideoRenderer> get localRendererStream => _localRendererController.stream;
  Stream<RTCVideoRenderer> get remoteRendererStream => _remoteRendererController.stream;
  Stream<Map<String, String>> get incomingCallStream => _incomingCallController.stream;
  Stream<List<Map<String, dynamic>>> get onlineUsersStream => _onlineUsersController.stream;

  void init() {
    _listenForIncomingCalls();
    _listenForOnlineUsers();
  }

  Future<void> createCall(String userId) async {
    await startCall(userId);
  }

  Future<void> startCall(String userId) async {
    _isOffer = true;
    _roomId = const Uuid().v4();
    await _getUserMedia();
    await _createPeerConnection();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await FirebaseFirestore.instance.collection('calls').doc(_roomId).set({
      'caller': currentUserId,
      'offer': offer.toMap(),
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('user_calls').doc(userId).set({
      'callId': _roomId,
      'caller': currentUserId,
      'action': 'incoming_call',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _conversationId = await FirebaseFirestore.instance.collection('conversations').add({
      'participants': [currentUserId, userId],
      'startTime': DateTime.now(),
      'createdAt': FieldValue.serverTimestamp(),
    }).then((doc) => doc.id);

    await _autoTranscriptionService.handleRecordingAndTranscription(conversationId: _conversationId!);
    _isInCall = true;
  }

  Future<void> autoConnect() async {
    await _getUserMedia();
    await _createPeerConnection();
  }

  Future<void> acceptCall(String callId) async {
    final doc = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
    final callerId = doc.data()?['caller'];
    if (callerId == null) throw Exception('Caller ID 없음');
    await answerCall(callId, callerId);
  }

  Future<void> answerCall(String callId, String callerId) async {
    _roomId = callId;
    _isOffer = false;
    await _getUserMedia();
    await _createPeerConnection();

    final doc = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
    final offer = doc.data()?['offer'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type'])
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'answer': answer.toMap(),
      'status': 'connected'
    });
    await FirebaseFirestore.instance.collection('user_calls').doc(currentUserId).delete();

    _conversationId = await FirebaseFirestore.instance.collection('conversations').add({
      'participants': [currentUserId, callerId],
      'startTime': DateTime.now(),
      'createdAt': FieldValue.serverTimestamp(),
    }).then((doc) => doc.id);

    await _autoTranscriptionService.handleRecordingAndTranscription(conversationId: _conversationId!);
    _isInCall = true;
  }

  Future<void> declineCall(String callId) async {
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'declined'});
    await FirebaseFirestore.instance.collection('user_calls').doc(currentUserId).delete();
  }

  Future<void> endCall() async {
    await _peerConnection?.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    _isInCall = false;

    if (_conversationId != null) {
      await _autoTranscriptionService.stopAndProcessRecording(conversationId: _conversationId!);
      await FirebaseFirestore.instance.collection('conversations').doc(_conversationId!).update({
        'endTime': DateTime.now(),
      });
    }
  }

  Future<void> _getUserMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onTrack = (event) {
      _remoteStream = event.streams[0];
    };
  }

  void setVideoRenderers(RTCVideoRenderer local, RTCVideoRenderer remote) {
    local.srcObject = _localStream;
    remote.srcObject = _remoteStream;
  }

  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) await Helper.switchCamera(videoTrack);
  }

  Future<void> toggleMute() async {
    final audioTrack = _localStream?.getAudioTracks().firstOrNull;
    if (audioTrack != null) audioTrack.enabled = !audioTrack.enabled;
  }

  Future<List<Map<String, dynamic>>> getOnlineUsers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('online_users')
        .where('isOnline', isEqualTo: true)
        .get();
    return snapshot.docs.map((d) => d.data()).cast<Map<String, dynamic>>().toList();
  }

  void _listenForIncomingCalls() {
    FirebaseFirestore.instance
        .collection('user_calls')
        .doc(currentUserId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data != null && data['action'] == 'incoming_call') {
        _incomingCallController.add({
          'callId': data['callId'],
          'callerId': data['caller'],
        });
      }
    });
  }

  void _listenForOnlineUsers() {
    FirebaseFirestore.instance
        .collection('online_users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      final users = snapshot.docs.map((d) => d.data()).cast<Map<String, dynamic>>().toList();
      _onlineUsersController.add(users);
    });
  }

  void disposeService() {
    _localRendererController.close();
    _remoteRendererController.close();
    _incomingCallController.close();
    _onlineUsersController.close();
    _localStream?.dispose();
    _peerConnection?.dispose();
    _autoTranscriptionService.dispose();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : this[0];
}
