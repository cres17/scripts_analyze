import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/widgets.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class CallService with ChangeNotifier {
  final _localRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final _remoteRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final _incomingCallController = StreamController<Map<String, String>>.broadcast();
  final _onlineUsersController = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<RTCVideoRenderer> get localRendererStream => _localRendererController.stream;
  Stream<RTCVideoRenderer> get remoteRendererStream => _remoteRendererController.stream;
  Stream<Map<String, String>> get incomingCallStream => _incomingCallController.stream;
  Stream<List<Map<String, dynamic>>> get onlineUsersStream => _onlineUsersController.stream;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _isConnectionFailed = false;
  String? _errorMessage;
  bool _isInCall = false;
  String _roomId = '';
  bool _isOffer = false;
  bool _isWebRTCInitialized = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 2;
  String? _callId;
  String? calleeId;
  Function(String callId, String callerId)? onIncomingCall;
  StreamSubscription? _candidatesSubscription;
  StreamSubscription? _callsSubscription;
  StreamSubscription? _callStatusSubscription;
  StreamSubscription? _onlineUsersSubscription;

  final _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun.stunprotocol.org:3478'},
      {
        'urls': 'turn:numb.viagenie.ca',
        'username': 'webrtc@live.com',
        'credential': 'muazkh'
      },
      {
        'urls': 'turn:relay.metered.ca:80',
        'username': 'e022e31fa58e23d9bc34a952',
        'credential': 'wIqjjtbAuuoOfmKr'
      }
    ],
    'sdpSemantics': 'unified-plan'
  };

  Timer? _heartbeatTimer;

  // 에뮬레이터 감지 캐시 변수
  bool? _isEmulator;
  
  // 에뮬레이터 감지 함수
  Future<bool> _isRunningOnEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        
        // 에뮬레이터 감지 조건들
        final isEmulator = 
          androidInfo.brand.toLowerCase().contains('google') &&
          (androidInfo.model.toLowerCase().contains('sdk') ||
           androidInfo.model.toLowerCase().contains('emulator') ||
           androidInfo.model.toLowerCase().contains('android sdk') ||
           androidInfo.product.toLowerCase().contains('sdk'));
        
        debugPrint('기기 정보: ${androidInfo.brand} ${androidInfo.model}');
        debugPrint('에뮬레이터 감지 결과: $isEmulator');
        
        return isEmulator;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        
        // iOS 시뮬레이터 감지
        final isSimulator = !iosInfo.isPhysicalDevice;
        
        debugPrint('기기 정보: ${iosInfo.model}');
        debugPrint('시뮬레이터 감지 결과: $isSimulator');
        
        return isSimulator;
      }
    } catch (e) {
      debugPrint('기기 정보 확인 오류: $e');
    }
    
    // 오류 발생 시 기본값으로 false 반환
    return false;
  }

  String get currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('경고: 로그인된 사용자가 없습니다!');
      return 'anonymous_user_${DateTime.now().millisecondsSinceEpoch}';
    }
    return user.uid;
  }
  
  bool get isConnectionFailed => _isConnectionFailed;
  String? get errorMessage => _errorMessage;
  bool get isInCall => _isInCall;

  void init() {
    debugPrint('CallService 초기화: currentUserId=${currentUserId}');
    _setupLocalRenderer();
    _cleanupOldCalls();
    _setUserOnline();
    _listenForOnlineUsers();
    
    listenForIncomingCalls((callId, callerId) {
      debugPrint('수신 통화 감지: callId=$callId, callerId=$callerId');
      _incomingCallController.add({'callId': callId, 'callerId': callerId});
    });
  }

  // 온라인 상태 설정
  Future<void> _setUserOnline() async {
    try {
      final userId = currentUserId;
      final displayName = '사용자 $userId'.substring(0, min(10, userId.length)); // ID 너무 길면 자르기
      
      // 먼저 오프라인 상태 감지 설정 (앱 종료 시 자동으로 오프라인 처리)
      final docRef = FirebaseFirestore.instance.collection('online_users').doc(userId);
      
      // Firestore에 온라인 상태 업데이트
      await docRef.set({
        'userId': userId,
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
        'displayName': displayName,
      }, SetOptions(merge: true)); // 기존 문서가 있으면 병합
      
      // 주기적으로 온라인 상태 업데이트 (heartbeat)
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!_isInCall) {
          try {
            await docRef.update({
              'lastSeen': FieldValue.serverTimestamp(),
              'isOnline': true,
            });
            debugPrint('온라인 상태 업데이트 (heartbeat)');
          } catch (e) {
            debugPrint('온라인 상태 업데이트 실패: $e');
          }
        }
      });
      
      // 앱 종료 시 오프라인 상태로 변경하기 위한 설정
      Future.delayed(Duration.zero, () {
        docRef.update({'isOnline': false}).whenComplete(() => 
          debugPrint('사용자 오프라인 상태로 변경됨')).onError((e, _) => 
          debugPrint('오프라인 상태 변경 실패: $e'));
      });
      
      debugPrint('사용자 온라인 상태로 설정됨: $userId');
    } catch (e) {
      debugPrint('온라인 상태 설정 오류: $e');
    }
  }
  
  // 온라인 사용자 목록 리스닝
  void _listenForOnlineUsers() {
    _onlineUsersSubscription?.cancel();
    
    _onlineUsersSubscription = FirebaseFirestore.instance
        .collection('online_users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      final List<Map<String, dynamic>> users = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] ?? '';
        
        // 자신은 제외
        if (userId != currentUserId) {
          users.add({
            'userId': userId,
            'displayName': data['displayName'] ?? '익명 사용자',
            'lastSeen': data['lastSeen'] ?? Timestamp.now(),
          });
        }
      }
      
      // 가장 최근에 접속한 사용자 순으로 정렬
      users.sort((a, b) {
        final aTime = (a['lastSeen'] as Timestamp).millisecondsSinceEpoch;
        final bTime = (b['lastSeen'] as Timestamp).millisecondsSinceEpoch;
        return bTime.compareTo(aTime);
      });
      
      debugPrint('온라인 사용자 목록 업데이트: ${users.length}명');
      for (var user in users) {
        debugPrint('- 온라인 사용자: ${user['displayName']} (${user['userId']})');
      }
      
      _onlineUsersController.add(users);
    }, onError: (e) {
      debugPrint('온라인 사용자 목록 리스닝 오류: $e');
    });
  }
  
  // 강제로 온라인 사용자 목록 갱신
  Future<List<Map<String, dynamic>>> getOnlineUsers() async {
    debugPrint('온라인 사용자 목록 새로고침 요청');
    try {
      // 먼저 자신의 온라인 상태 업데이트 (Firebase 인덱싱 대기를 위해)
      await FirebaseFirestore.instance
          .collection('online_users')
          .doc(currentUserId)
          .update({
            'lastSeen': FieldValue.serverTimestamp(),
            'isOnline': true,
          });
      
      // 잠시 대기 후 목록 가져오기 (Firebase 인덱싱 대기)
      await Future.delayed(const Duration(milliseconds: 500));
      
      final snapshot = await FirebaseFirestore.instance
          .collection('online_users')
          .where('isOnline', isEqualTo: true)
          .get();
      
      final List<Map<String, dynamic>> users = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] ?? '';
        
        // 자신은 제외
        if (userId != currentUserId) {
          users.add({
            'userId': userId,
            'displayName': data['displayName'] ?? '익명 사용자',
            'lastSeen': data['lastSeen'] ?? Timestamp.now(),
          });
        }
      }
      
      users.sort((a, b) {
        final aTime = (a['lastSeen'] as Timestamp).millisecondsSinceEpoch;
        final bTime = (b['lastSeen'] as Timestamp).millisecondsSinceEpoch;
        return bTime.compareTo(aTime);
      });
      
      debugPrint('온라인 사용자 목록 새로고침 결과: ${users.length}명');
      for (var user in users) {
        debugPrint('- 온라인 사용자: ${user['displayName']} (${user['userId']})');
      }
      
      _onlineUsersController.add(users);
      return users;
    } catch (e) {
      debugPrint('온라인 사용자 목록 가져오기 오류: $e');
      return [];
    }
  }

  Future<void> _cleanupOldCalls() async {
    try {
      await FirebaseFirestore.instance
          .collection('user_calls')
          .doc(currentUserId)
          .delete();
      debugPrint('이전 사용자 통화 문서 삭제됨');
    } catch (e) {
      // 문서가 없으면 무시
    }
  }

  Future<void> _setupLocalRenderer() async {
    debugPrint('로컬 렌더러 초기화');
    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
  }

  Future<void> _setupRemoteRenderer() async {
    debugPrint('원격 렌더러 초기화');
    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer!.initialize();
  }

  Future<void> autoConnect() async {
    int retryCount = 0;
    const int maxRetries = 2;
    const Duration retryDelay = Duration(seconds: 1);
    
    while (retryCount <= maxRetries) {
      try {
        if (retryCount > 0) {
          debugPrint('연결 재시도 #$retryCount...');
        }
        
        // 이전 연결 정리
        if (_peerConnection != null) {
          await _peerConnection!.close();
          _peerConnection = null;
        }
        
        // 순서대로 초기화 진행
        await _getUserMedia();
        await _setupLocalRenderer();
        await _createPeerConnection();
        
        if (_peerConnection != null) {
          debugPrint('자동 연결 성공!');
          _isConnectionFailed = false;
          _errorMessage = null;
          notifyListeners();
          return;
        } else {
          throw Exception('피어 연결 생성 실패');
        }
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          debugPrint('최대 재시도 횟수 초과: $e');
          _isConnectionFailed = true;
          _errorMessage = '연결 재시도 실패: ${e.toString()}';
          notifyListeners();
          throw Exception('연결 시도 $maxRetries회 실패: ${e.toString()}');
        }
        
        debugPrint('재시도 전 대기 중...');
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) {
      debugPrint('피어 연결이 이미 존재합니다. 기존 연결을 재사용합니다.');
      return;
    }
    
    debugPrint('새 피어 연결 생성 중...');
    
    try {
      // 로컬 스트림이 없으면 먼저 가져오기
      if (_localStream == null) {
        await _getUserMedia();
      }
      
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };
      
      _peerConnection = await createPeerConnection(configuration);
      
      if (_peerConnection == null) {
        throw Exception('피어 연결 객체를 생성할 수 없습니다.');
      }
      
      debugPrint('피어 연결 객체 생성 성공');
      
      // 로컬 스트림의 트랙 추가
      debugPrint('미디어 트랙 추가 중...');
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
        debugPrint('미디어 트랙 추가: ${track.kind}');
      });
      
      // 연결 상태 확인을 위한 이벤트 핸들러
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('피어 연결 상태 변경: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            debugPrint('피어 연결 성공: 통화가 활성화되었습니다!');
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            debugPrint('피어 연결 실패: 통화를 연결할 수 없습니다.');
            break;
          default:
            break;
        }
      };
      
      // 다른 이벤트 핸들러 설정...
      _peerConnection!.onIceCandidate = (candidate) {
        debugPrint('ICE 후보 생성됨');
        _sendIceCandidate(candidate);
      };
      
      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('ICE 연결 상태 변경: $state');
        switch (state) {
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
          case RTCIceConnectionState.RTCIceConnectionStateCompleted:
            debugPrint('ICE 연결 성공: 미디어가 흐르고 있습니다!');
            _isConnectionFailed = false;
            _errorMessage = null;
            _reconnectAttempts = 0;
            notifyListeners();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
          case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
            // 재연결 시도
            if (_reconnectAttempts < maxReconnectAttempts) {
              _reconnectAttempts++;
              debugPrint('연결 끊김: 재연결 시도 $_reconnectAttempts/$maxReconnectAttempts');
              // 재연결 로직 구현
              _attemptReconnect();
            } else {
              _isConnectionFailed = true;
              _errorMessage = '연결이 끊겼습니다. 통화를 다시 시도해주세요.';
              notifyListeners();
            }
            break;
          default:
            break;
        }
      };
      
      _peerConnection!.onTrack = (event) {
        debugPrint('원격 미디어 트랙 수신됨: ${event.track.kind}');
        
        // 비디오 트랙인 경우
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          debugPrint('원격 비디오 트랙을 원격 스트림에 연결합니다.');
          _remoteStream = event.streams[0];
          
          if (_remoteRenderer != null) {
            _remoteRenderer!.srcObject = _remoteStream;
            _remoteRendererController.add(_remoteRenderer!);
            debugPrint('원격 비디오가 렌더러에 연결되었습니다.');
          }
        } 
        // 오디오 트랙인 경우
        else if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
          debugPrint('원격 오디오 트랙 수신됨');
          // 비디오 트랙이 없는 경우 (에뮬레이터)
          if (_remoteStream == null) {
            _remoteStream = event.streams[0];
            debugPrint('오디오 전용: 원격 스트림이 설정되었습니다.');
          }
        }
        
        notifyListeners();
      };
      
    } catch (e) {
      debugPrint('피어 연결 생성 오류: $e');
      _isConnectionFailed = true;
      _errorMessage = '통화 연결을 설정할 수 없습니다: ${e.toString()}';
      
      // 리소스 정리
      await _peerConnection?.close();
      _peerConnection = null;
      
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _attemptReconnect() async {
    try {
      // 기존 연결 정리
      await _peerConnection?.close();
      _peerConnection = null;
      
      // 새 연결 시도
      await _createPeerConnection();
      
      // 기존 통화가 오퍼였으면 오퍼 다시 생성
      if (_isOffer && _roomId.isNotEmpty) {
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        await FirebaseFirestore.instance.collection('calls').doc(_roomId).update({
          'offer': offer.toMap(),
          'status': 'reconnecting',
        });
      }
      // 기존 통화가 응답이었으면 오퍼 가져와서 응답 다시 생성
      else if (!_isOffer && _roomId.isNotEmpty) {
        final offer = await _getOffer(_roomId);
        if (offer != null) {
          await _peerConnection!.setRemoteDescription(offer);
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          await _saveAnswer(_roomId, answer);
        }
      }
      
    } catch (e) {
      debugPrint('재연결 시도 오류: $e');
      _isConnectionFailed = true;
      _errorMessage = '재연결 실패: ${e.toString()}';
      notifyListeners();
    }
  }

  // 화상 통화 시작 - 발신자 측
  Future<String?> startCall(String userId) async {
    try {
      debugPrint('화상 통화 시작 - 사용자 ID: $userId');
      
      // 기존 통화 정리
      _cleanupCall();
      
      // 발신자 설정
      _isOffer = true;
      calleeId = userId;
      
      // 웹RTC 초기화 확인
      if (!_isWebRTCInitialized) {
        await _initializeWebRTC();
      }
      
      // 로컬 미디어 스트림 획득
      await _getUserMedia();
      
      // 피어 연결 생성
      await _createPeerConnection();
      
      // 오퍼 생성
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      // 오퍼 저장 및 통화 ID 반환
      final callId = await _saveOffer(offer);
      _callId = callId;
      _isInCall = true;
      
      return callId;
    } catch (e) {
      debugPrint('통화 시작 오류: $e');
      _isConnectionFailed = true;
      _errorMessage = '통화를 시작할 수 없습니다: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  // 화상 통화 응답 - 수신자 측
  Future<bool> answerCall(String callId, String callerId) async {
    try {
      debugPrint('화상 통화 응답 - 통화 ID: $callId, 발신자 ID: $callerId');
      
      // 기존 통화 정리
      _cleanupCall();
      
      // 수신자 설정
      _isOffer = false;
      calleeId = callerId;
      _roomId = callId;
      
      // 웹RTC 초기화 확인
      if (!_isWebRTCInitialized) {
        await _initializeWebRTC();
      }
      
      // 로컬 미디어 스트림 획득
      await _getUserMedia();
      
      // 피어 연결 생성
      await _createPeerConnection();
      
      // 오퍼 가져오기
      final offer = await _getOffer(callId);
      if (offer == null) {
        throw Exception('오퍼를 가져올 수 없습니다.');
      }
      
      // 원격 설명 설정 (오퍼)
      await _peerConnection!.setRemoteDescription(offer);
      
      // 응답 생성
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      
      // 응답 저장
      await _saveAnswer(callId, answer);
      _isInCall = true;
      
      return true;
    } catch (e) {
      debugPrint('통화 응답 오류: $e');
      _isConnectionFailed = true;
      _errorMessage = '통화에 응답할 수 없습니다: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // 통화 거절 - 수신자 측
  Future<void> declineCall(String callId) async {
    try {
      debugPrint('통화 거절 - 통화 ID: $callId');
      
      // 통화 상태 업데이트
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'declined',
      });
      
      // 사용자 통화 문서 삭제
      await FirebaseFirestore.instance
          .collection('user_calls')
          .doc(currentUserId)
          .delete();
      
    } catch (e) {
      debugPrint('통화 거절 오류: $e');
    }
  }

  // 통화 종료
  Future<void> endCall() async {
    try {
      debugPrint('통화 종료');
      
      if (_roomId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('calls').doc(_roomId).update({
          'status': 'ended',
          'ended_at': FieldValue.serverTimestamp(),
        });
      }
      
      _cleanupCall();
    } catch (e) {
      debugPrint('통화 종료 오류: $e');
      // 오류가 있더라도 리소스는 정리
      _cleanupCall();
    }
  }

  // 통화 리소스 정리
  Future<void> _cleanupCall({bool notifyFirebase = true}) async {
    debugPrint('통화 리소스 정리 시작');
    
    // 피어 연결 종료
    await _peerConnection?.close();
    _peerConnection = null;
    
    // 로컬 스트림 종료
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    
    // 원격 스트림 참조 해제
    _remoteStream = null;
    
    // 구독 취소
    _callStatusSubscription?.cancel();
    _candidatesSubscription?.cancel();
    
    // 상태 초기화
    _isInCall = false;
    _isConnectionFailed = false;
    _errorMessage = null;
    _isOffer = false;
    _reconnectAttempts = 0;
    
    if (notifyFirebase && _roomId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('calls').doc(_roomId).update({
          'status': 'ended',
          'ended_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Firestore 통화 종료 업데이트 오류: $e');
      }
    }
    
    _roomId = '';
    _callId = null;
    
    // UI 업데이트
    notifyListeners();
    
    debugPrint('통화 리소스 정리 완료');
  }

  MediaStream? get localStream => _localStream;

  bool toggleAudio() {
    if (_localStream == null || _localStream!.getAudioTracks().isEmpty) return false;
    final enabled = !_localStream!.getAudioTracks()[0].enabled;
    for (var track in _localStream!.getAudioTracks()) {
      track.enabled = enabled;
    }
    debugPrint('오디오 ${enabled ? '활성화' : '비활성화'}');
    return enabled;
  }

  bool toggleVideo() {
    if (_localStream == null || _localStream!.getVideoTracks().isEmpty) return false;
    final enabled = !_localStream!.getVideoTracks()[0].enabled;
    for (var track in _localStream!.getVideoTracks()) {
      track.enabled = enabled;
    }
    debugPrint('비디오 ${enabled ? '활성화' : '비활성화'}');
    return enabled;
  }

  Future<bool> switchCamera() async {
    if (_localStream == null || _localStream!.getVideoTracks().isEmpty) return false;
    final track = _localStream!.getVideoTracks()[0];
    try {
      await Helper.switchCamera(track);
      debugPrint('카메라 전환 성공');
      return true;
    } catch (e) {
      debugPrint('카메라 전환 실패: $e');
      return false;
    }
  }

  void disposeService() {
    debugPrint('CallService 정리');
    
    // 타이머 취소
    _heartbeatTimer?.cancel();
    
    // 온라인 상태 해제
    try {
      FirebaseFirestore.instance
          .collection('online_users')
          .doc(currentUserId)
          .update({'isOnline': false})
          .then((_) => debugPrint('사용자 오프라인 상태로 변경됨'));
    } catch (e) {
      debugPrint('오프라인 상태 변경 실패: $e');
    }
    
    _candidatesSubscription?.cancel();
    _callsSubscription?.cancel();
    _callStatusSubscription?.cancel();
    _onlineUsersSubscription?.cancel();
    
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    
    _localRendererController.close();
    _remoteRendererController.close();
    _incomingCallController.close();
    _onlineUsersController.close();
    
    endCall();
  }

  Future<void> _initializeWebRTC() async {
    try {
      debugPrint('WebRTC 초기화 시작...');
      // WebRTC 기본 초기화 작업 (특별한 초기화가 필요 없으면 아래 주석 해제)
      // await WebRTC.initialize();
      _isWebRTCInitialized = true;
      debugPrint('WebRTC 초기화 완료');
    } catch (e) {
      debugPrint('WebRTC 초기화 실패: $e');
      _isWebRTCInitialized = false;
      throw Exception('WebRTC 초기화 실패: ${e.toString()}');
    }
  }

  // 에뮬레이터 여부에 따라 미디어 제약 조건을 조정
  Future<Map<String, dynamic>> _getMediaConstraints() async {
    final isEmulator = await _isRunningOnEmulator();
    final mediaConstraints = <String, dynamic>{
      'audio': true
    };
    
    if (!isEmulator) {
      // 실제 기기에서는 비디오 활성화
      mediaConstraints['video'] = {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      };
      debugPrint('실제 기기에서 비디오 활성화');
    } else {
      // 에뮬레이터에서는 비디오 비활성화
      mediaConstraints['video'] = false;
      debugPrint('에뮬레이터에서 비디오 비활성화 (오디오만 사용)');
    }
    
    return mediaConstraints;
  }

  Future<void> _getUserMedia() async {
    debugPrint('미디어 스트림 획득 시작...');
    
    // 이미 로컬 스트림이 있으면 재사용
    if (_localStream != null) {
      debugPrint('기존 로컬 미디어 스트림 재사용');
      return;
    }
    
    try {
      // 에뮬레이터 여부 확인
      final isEmulator = await _isRunningOnEmulator();
      
      // 미디어 제약 조건 구성
      final mediaConstraints = <String, dynamic>{
        'audio': true
      };
      
      // 실제 기기인 경우에만 비디오 활성화
      if (!isEmulator) {
        mediaConstraints['video'] = {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
          'optional': [],
        };
        debugPrint('실제 기기에서 비디오 활성화');
      } else {
        // 에뮬레이터에서는 비디오 비활성화
        mediaConstraints['video'] = false;
        debugPrint('에뮬레이터에서 비디오 비활성화 (오디오만 사용)');
      }
      
      // 미디어 스트림 획득
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      if (_localStream == null) {
        throw Exception('미디어 스트림을 가져올 수 없습니다.');
      }
      
      // 로컬 렌더러에 스트림 설정
      if (_localRenderer != null) {
        _localRenderer!.srcObject = _localStream;
        _localRendererController.add(_localRenderer!);
      }
      
      debugPrint('미디어 스트림 획득 완료: 비디오 트랙 ${_localStream!.getVideoTracks().length}개, 오디오 트랙 ${_localStream!.getAudioTracks().length}개');
    } catch (e) {
      debugPrint('미디어 스트림 획득 실패: $e');
      throw Exception('미디어 스트림 획득 실패: ${e.toString()}');
    }
  }

  void setVideoRenderers(RTCVideoRenderer localRenderer, RTCVideoRenderer remoteRenderer) {
    debugPrint('비디오 렌더러 설정');
    
    // 로컬 스트림 설정
    if (_localStream != null) {
      localRenderer.srcObject = _localStream;
    }
    
    // 원격 스트림 설정
    if (_remoteStream != null) {
      remoteRenderer.srcObject = _remoteStream;
    }
  }

  Future<String> _saveOffer(RTCSessionDescription offer) async {
    try {
      final callId = const Uuid().v4();
      _roomId = callId;
      
      // 통화 정보 저장
      await FirebaseFirestore.instance.collection('calls').doc(callId).set({
        'caller': currentUserId,
        'offer': offer.toMap(),
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });
      
      // 상대방에게 통화 요청 알림
      await FirebaseFirestore.instance
          .collection('user_calls')
          .doc(calleeId)
          .set({
            'callId': callId,
            'caller': currentUserId,
            'action': 'incoming_call',
            'timestamp': FieldValue.serverTimestamp(),
          });
      
      // 통화 상태 리스너 설정
      _listenForCallStatus(callId);
      
      // ICE 후보 리스너 설정
      _listenForCandidates(callId);
      
      return callId;
    } catch (e) {
      debugPrint('오퍼 저장 오류: $e');
      throw Exception('오퍼 저장 오류: ${e.toString()}');
    }
  }

  Future<RTCSessionDescription?> _getOffer(String roomId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('calls').doc(roomId).get();
      
      if (!doc.exists || doc.data() == null) {
        throw Exception('통화 정보를 찾을 수 없습니다.');
      }
      
      final data = doc.data()!;
      final offerMap = data['offer'];
      
      if (offerMap == null) {
        throw Exception('오퍼 정보가 없습니다.');
      }
      
      // 통화 상태 리스너 설정
      _listenForCallStatus(roomId);
      
      // ICE 후보 리스너 설정
      _listenForCandidates(roomId);
      
      // 오퍼 객체 생성
      return RTCSessionDescription(
        offerMap['sdp'],
        offerMap['type'],
      );
    } catch (e) {
      debugPrint('오퍼 가져오기 오류: $e');
      throw Exception('오퍼 가져오기 오류: ${e.toString()}');
    }
  }

  Future<void> _saveAnswer(String roomId, RTCSessionDescription answer) async {
    try {
      await FirebaseFirestore.instance.collection('calls').doc(roomId).update({
        'answer': answer.toMap(),
        'status': 'ongoing',
      });
      
      // 통화 상대방에게 알림 (사용자 통화 문서 삭제)
      await FirebaseFirestore.instance
          .collection('user_calls')
          .doc(currentUserId)
          .delete();
      
      _isInCall = true;
    } catch (e) {
      debugPrint('응답 저장 오류: $e');
      throw Exception('응답 저장 오류: ${e.toString()}');
    }
  }

  void _listenForCallStatus(String roomId) {
    _roomId = roomId;
    
    _callStatusSubscription?.cancel();
    
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(roomId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data != null) {
        final status = data['status'];
        debugPrint('통화 상태 변경: $status');
        
        if (status == 'ongoing') {
          _isInCall = true;
          notifyListeners();
        } else if (status == 'ended' || status == 'declined') {
          _isInCall = false;
          _cleanupCall(notifyFirebase: false);
          notifyListeners();
        }
      }
    }, onError: (e) {
      debugPrint('통화 상태 리스너 오류: $e');
    });
  }

  void _listenForCandidates(String roomId) {
    _candidatesSubscription?.cancel();
    
    _candidatesSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(roomId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['sender'] != currentUserId) {
            debugPrint('원격 ICE 후보 수신됨');
            _peerConnection?.addCandidate(RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ));
          }
        }
      }
    }, onError: (e) {
      debugPrint('ICE 후보 리스너 오류: $e');
    });
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_roomId.isEmpty) {
      debugPrint('ICE 후보를 보낼 수 없음: roomId가 없습니다.');
      return;
    }
    
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(_roomId)
          .collection('candidates')
          .add({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'sender': currentUserId,
          });
    } catch (e) {
      debugPrint('ICE 후보 전송 오류: $e');
    }
  }

  bool get isMuted {
    if (_localStream == null || _localStream!.getAudioTracks().isEmpty) return false;
    return !_localStream!.getAudioTracks()[0].enabled;
  }

  Future<bool> toggleMute() async {
    return toggleAudio();
  }

  // 수신 통화 리스너 설정 메서드
  void listenForIncomingCalls(Function(String callId, String callerId) callback) {
    debugPrint('수신 통화 리스너 설정 중...');
    onIncomingCall = callback;

    _callsSubscription?.cancel();
    
    _callsSubscription = FirebaseFirestore.instance
        .collection('user_calls')
        .doc(currentUserId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      debugPrint('수신 통화 문서 변경: $data');
      if (data != null && data['action'] == 'incoming_call') {
        final callId = data['callId'];
        final callerId = data['caller'];
        debugPrint('수신 통화 감지: callId=$callId, callerId=$callerId');
        onIncomingCall?.call(callId, callerId);
      }
    }, onError: (e) {
      debugPrint('수신 통화 리스너 오류: $e');
    });
    
    FirebaseFirestore.instance
        .collection('user_calls')
        .doc(currentUserId)
        .get()
        .then((doc) {
      final data = doc.data();
      debugPrint('초기 수신 통화 문서 상태: $data');
      if (data != null && data['action'] == 'incoming_call') {
        final callId = data['callId'];
        final callerId = data['caller'];
        debugPrint('기존 수신 통화 감지: callId=$callId, callerId=$callerId');
        onIncomingCall?.call(callId, callerId);
      }
    }).catchError((e) {
      debugPrint('초기 수신 통화 확인 오류: $e');
    });
  }

  // 기존 메서드 호환성을 위한 createCall
  Future<void> createCall(String targetUserId) async {
    debugPrint('통화 생성 호출 - 대상 ID: $targetUserId');
    // 새 메서드 startCall로 리디렉션
    await startCall(targetUserId);
  }

  // 기존 메서드 호환성을 위한 acceptCall
  Future<void> acceptCall(String callId) async {
    debugPrint('통화 수락 호출 - 통화 ID: $callId');
    
    // 발신자 ID 가져오기
    try {
      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      
      if (!doc.exists) {
        throw Exception('통화 정보를 찾을 수 없습니다.');
      }
      
      final data = doc.data();
      if (data == null) {
        throw Exception('통화 데이터가 없습니다.');
      }
      
      final callerId = data['caller'];
      if (callerId == null) {
        throw Exception('발신자 정보가 없습니다.');
      }
      
      // 새 메서드 answerCall로 리디렉션
      await answerCall(callId, callerId);
    } catch (e) {
      debugPrint('통화 수락 오류: $e');
      _isConnectionFailed = true;
      _errorMessage = '통화를 수락할 수 없습니다: ${e.toString()}';
      notifyListeners();
      throw Exception('통화 수락 실패: ${e.toString()}');
    }
  }
}

int min(int a, int b) {
  return (a < b) ? a : b;
}
