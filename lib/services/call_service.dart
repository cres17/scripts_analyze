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
  bool _isConnectionFailed = false;
  String? _errorMessage;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isConnectionFailed => _isConnectionFailed;
  String? get errorMessage => _errorMessage;

  Future<void> _createPeerConnection() async {
    try {
      // STUN 서버와 TURN 서버 모두 추가
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {
            'urls': 'turn:numb.viagenie.ca',
            'username': 'webrtc@live.com',
            'credential': 'muazkh'
          }
        ],
        'sdpSemantics': 'unified-plan'
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
          try {
            FirebaseFirestore.instance
                .collection('calls')
                .doc(_roomId)
                .collection('candidates')
                .add(candidate.toMap());
          } catch (e) {
            debugPrint('ICE candidate 저장 오류: $e');
            _setError('ICE candidate 저장 실패');
          }
        }
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('ICE 연결 상태: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed || 
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _setError('P2P 연결 실패');
        }
      };
    } catch (e) {
      debugPrint('_createPeerConnection 오류: $e');
      _setError('PeerConnection 생성 실패');
      rethrow;
    }
  }

  void _setError(String message) {
    _isConnectionFailed = true;
    _errorMessage = message;
    notifyListeners();
  }

  Future<String> createCall(String calleeId) async {
    try {
      _roomId = FirebaseFirestore.instance.collection('calls').doc().id;
      await _createPeerConnection();

      // 미디어 스트림 초기화
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true, 
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
          'optional': [],
        }
      });
      
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
          .doc(_roomId)
          .set({
        'caller': currentUserId,
        'callee': calleeId,
        'offer': offer.toMap(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'waiting',
      });

      // Answer 대기
      FirebaseFirestore.instance
          .collection('calls')
          .doc(_roomId)
          .snapshots()
          .listen((doc) async {
        try {
          final data = doc.data();
          if (data != null && data['answer'] != null && _peerConnection != null) {
            final answer = data['answer'];
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(answer['sdp'], answer['type']),
            );
            
            // 상태 업데이트
            await FirebaseFirestore.instance
                .collection('calls')
                .doc(_roomId)
                .update({'status': 'connected'});
          }
        } catch (e) {
          debugPrint('Answer 처리 오류: $e');
          _setError('원격 응답 처리 실패');
        }
      });

      // ICE Candidate 수신 대기
      FirebaseFirestore.instance
          .collection('calls')
          .doc(_roomId)
          .collection('candidates')
          .snapshots()
          .listen((snapshot) {
        try {
          for (var doc in snapshot.docs) {
            // Firestore에서 새로운 candidate를 가져왔을 때만 처리
            if (_peerConnection != null && doc.metadata.hasPendingWrites == false) {
              final data = doc.data();
              // candidate가 callee(상대방)에서 온 것인지 확인
              if (data['sdpMid'] != null && data['sdpMLineIndex'] != null && data['candidate'] != null) {
                _peerConnection!.addCandidate(RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('ICE candidate 처리 오류: $e');
          _setError('ICE 후보 처리 실패');
        }
      });

      return _roomId;
    } catch (e) {
      debugPrint('createCall 오류: $e');
      _setError('통화 생성 실패');
      rethrow;
    }
  }

  late String _roomId;

  Future<void> joinCall(String roomId) async {
    try {
      _roomId = roomId;
      await _createPeerConnection();

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true, 
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
          'optional': [],
        }
      });
      
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      final localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;
      _localRendererController.add(localRenderer);

      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(roomId)
          .get();

      if (!doc.exists) {
        _setError('통화방이 존재하지 않습니다');
        return;
      }

      final data = doc.data();
      if (data == null || data['offer'] == null) {
        _setError('오퍼 정보가 없습니다');
        return;
      }

      await _peerConnection!.setRemoteDescription(RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      ));

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await FirebaseFirestore.instance
          .collection('calls')
          .doc(roomId)
          .update({
            'answer': answer.toMap(),
            'status': 'connected'
          });

      FirebaseFirestore.instance
          .collection('calls')
          .doc(roomId)
          .collection('candidates')
          .snapshots()
          .listen((snapshot) {
        try {
          for (var doc in snapshot.docs) {
            // Firestore에서 새로운 candidate를 가져왔을 때만 처리
            if (_peerConnection != null && doc.metadata.hasPendingWrites == false) {
              final data = doc.data();
              if (data['sdpMid'] != null && data['sdpMLineIndex'] != null && data['candidate'] != null) {
                _peerConnection!.addCandidate(RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('ICE candidate 처리 오류: $e');
          _setError('ICE 후보 처리 실패');
        }
      });
    } catch (e) {
      debugPrint('joinCall 오류: $e');
      _setError('통화 참여 실패');
      rethrow;
    }
  }

  Future<void> autoConnect() async {
    try {
      // 1. 내가 호출된 통화가 있는지 확인
      final incomingCallsSnapshot = await FirebaseFirestore.instance
          .collection('calls')
          .where('callee', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'waiting')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (incomingCallsSnapshot.docs.isNotEmpty) {
        // 내가 호출 당한 상태면 즉시 join
        final roomId = incomingCallsSnapshot.docs.first.id;
        await joinCall(roomId);
        return;
      }

      // 2. 대기 중인 다른 사용자 찾기
      final waitingUsersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: 'available')
          .where('uid', isNotEqualTo: currentUserId)
          .limit(1)
          .get();

      if (waitingUsersSnapshot.docs.isNotEmpty) {
        final calleeId = waitingUsersSnapshot.docs.first.id;
        await createCall(calleeId);
        return;
      }

      // 3. 사용 가능한 사용자가 없으면 대기 상태로 변경
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .set({'status': 'available', 'timestamp': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      
      // 4. 누군가 나를 호출할 때까지 대기
      debugPrint('사용 가능한 사용자 없음. 대기 상태로 전환');
    } catch (e) {
      debugPrint('autoConnect 오류: $e');
      _setError('자동 연결 실패');
    }
  }
  
  void listenForMatchedRoom(String userId) {
    FirebaseFirestore.instance
        .collection('calls')
        .where('callee', isEqualTo: userId)
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final roomId = snapshot.docs.first.id;
        joinCall(roomId);
      }
    }, onError: (e) {
      debugPrint('통화 수신 리스너 오류: $e');
      _setError('통화 알림 수신 실패');
    });
  }

  Future<void> endCall() async {
    try {
      await _peerConnection?.close();
      _peerConnection = null;
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      
      // 통화 상태 업데이트
      if (_roomId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(_roomId)
            .update({'status': 'ended'});
      }
      
      // 사용자 상태 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .update({'status': 'offline'});
          
      notifyListeners();
    } catch (e) {
      debugPrint('endCall 오류: $e');
    }
  }

  void disposeService() {
    _localRendererController.close();
    _remoteRendererController.close();
  }

  // 미디어 스트림 getter 추가
  MediaStream? get localStream => _localStream;
  
  // 오디오 토글 메서드
  bool toggleAudio() {
    if (_localStream == null) return false;
    
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isEmpty) return false;
    
    final enabled = !audioTracks[0].enabled;
    for (var track in audioTracks) {
      track.enabled = enabled;
    }
    return enabled;
  }
  
  // 비디오 토글 메서드
  bool toggleVideo() {
    if (_localStream == null) return false;
    
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return false;
    
    final enabled = !videoTracks[0].enabled;
    for (var track in videoTracks) {
      track.enabled = enabled;
    }
    return enabled;
  }
  
  // 카메라 전환 메서드
  Future<bool> switchCamera() async {
    if (_localStream == null) return false;
    
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return false;
    
    try {
      await Helper.switchCamera(videoTracks[0]);
      return true;
    } catch (e) {
      debugPrint('카메라 전환 오류: $e');
      return false;
    }
  }
}
