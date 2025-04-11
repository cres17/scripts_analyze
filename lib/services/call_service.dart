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

  Future<String> createCall(String calleeId) async {
  _roomId = FirebaseFirestore.instance.collection('calls').doc('active').collection('rooms').doc().id;
  await _createPeerConnection();

  // 미디어 스트림 초기화
  _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
  for (var track in _localStream!.getTracks()) {
    _peerConnection!.addTrack(track, _localStream!);
  }

  final localRenderer = RTCVideoRenderer();
  await localRenderer.initialize();
  localRenderer.srcObject = _localStream;
  _localRendererController.add(localRenderer);

  // Offer 생성
  final offer = await _peerConnection!.createOffer();
  await _peerConnection!.setLocalDescription(offer);

  // Firestore에 저장
  await FirebaseFirestore.instance
      .collection('calls')
      .doc('active')
      .collection('rooms')
      .doc(_roomId)
      .set({
    'caller': currentUserId,
    'callee': calleeId,
    'offer': offer.toMap(),
  });

  // Answer 대기
  FirebaseFirestore.instance
      .collection('calls')
      .doc('active')
      .collection('rooms')
      .doc(_roomId)
      .snapshots()
      .listen((doc) async {
    final data = doc.data();
    if (data != null && data['answer'] != null) {
      final answer = data['answer'];
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    }
  });

  // ICE Candidate 수신 대기
  FirebaseFirestore.instance
      .collection('calls')
      .doc('active')
      .collection('rooms')
      .doc(_roomId)
      .collection('candidates')
      .snapshots()
      .listen((snapshot) {
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data['type'] == 'answer') continue; // 자기 자신이 보낸 offer는 제외
      _peerConnection!.addCandidate(RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      ));
    }
  });

  return _roomId;
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
  Future<void> autoConnect() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('calls')
      .doc('active')
      .collection('rooms')
      .where('callee', isEqualTo: currentUserId)
      .get();

  if (snapshot.docs.isNotEmpty) {
    // 내가 호출 당한 상태면 즉시 join
    final roomId = snapshot.docs.first.id;
    await joinCall(roomId);
  } else {
    // 상대를 지정하거나 자동 선택해서 createCall 호출
    const calleeId = 'receiverUserId'; // TODO: 자동 매칭 로직 구현
    await createCall(calleeId);
  }
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
