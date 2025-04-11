import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CallService with ChangeNotifier {
  final _localRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final _remoteRendererController = StreamController<RTCVideoRenderer>.broadcast();

  Stream<RTCVideoRenderer> get localRendererStream => _localRendererController.stream;
  Stream<RTCVideoRenderer> get remoteRendererStream => _remoteRendererController.stream;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config);
    _remoteStream = await createLocalMediaStream('remote');

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        final renderer = RTCVideoRenderer();
        renderer.initialize().then((_) {
          renderer.srcObject = _remoteStream;
          _remoteRendererController.add(renderer);
        });
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        FirebaseFirestore.instance
            .collection('calls')
            .doc('active')
            .collection('rooms')
            .doc(_roomId)
            .collection('candidates')
            .add(candidate.toMap());
      }
    };
  }

  late String _roomId;

  Future<void> joinCall(String roomId) async {
    _roomId = roomId;
    await _createPeerConnection();

    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    final localRenderer = RTCVideoRenderer();
    await localRenderer.initialize();
    localRenderer.srcObject = _localStream;
    _localRendererController.add(localRenderer);

    final doc = await FirebaseFirestore.instance
        .collection('calls')
        .doc('active')
        .collection('rooms')
        .doc(roomId)
        .get();

    if (!doc.exists) return;

    final data = doc.data();
    if (data == null || data['offer'] == null) return;

    await _peerConnection!.setRemoteDescription(RTCSessionDescription(
      data['offer']['sdp'],
      data['offer']['type'],
    ));

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await FirebaseFirestore.instance
        .collection('calls')
        .doc('active')
        .collection('rooms')
        .doc(roomId)
        .update({'answer': answer.toMap()});

    FirebaseFirestore.instance
        .collection('calls')
        .doc('active')
        .collection('rooms')
        .doc(roomId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['type'] == 'offer') continue;
        _peerConnection!.addCandidate(RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        ));
      }
    });
  }

  void listenForMatchedRoom(String userId) {
    FirebaseFirestore.instance
        .collection('calls')
        .doc('active')
        .collection('rooms')
        .where('callee', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final roomId = snapshot.docs.first.id;
        joinCall(roomId);
      }
    });
  }

  Future<void> endCall() async {
    await _peerConnection?.close();
    _peerConnection = null;
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    notifyListeners();
  }

  void disposeService() {
    _localRendererController.close();
    _remoteRendererController.close();
  }
}
