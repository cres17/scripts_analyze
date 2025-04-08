import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:isolate';
import 'dart:async';

import 'audio_recording_service.dart';
import 'storage_service.dart';
import 'whisper_service.dart';
import 'gpt_service.dart';

class CallService {
  // WebRTC 관련 객체
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // 서비스 객체들
  final AudioRecordingService _audioRecordingService = AudioRecordingService();
  final StorageService _storageService = StorageService();
  final WhisperService _whisperService = WhisperService();
  final GptService _gptService = GptService();
  
  // 현재 통화 상태 정보
  String? _currentConversationId;
  DateTime? _callStartTime;
  
  // 통화 상태 관련 controllers
  final StreamController<RTCVideoRenderer> _localRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final StreamController<RTCVideoRenderer> _remoteRendererController = StreamController<RTCVideoRenderer>.broadcast();
  final StreamController<CallState> _callStateController = StreamController<CallState>.broadcast();
  
  // 스트림 getters
  Stream<RTCVideoRenderer> get localRendererStream => _localRendererController.stream;
  Stream<RTCVideoRenderer> get remoteRendererStream => _remoteRendererController.stream;
  Stream<CallState> get callStateStream => _callStateController.stream;
  
  // 현재 통화 상태
  CallState _currentCallState = CallState.idle;
  CallState get currentCallState => _currentCallState;
  
  // 생성자
  CallService() {
    _initialize();
  }
  
  // 초기 설정
  Future<void> _initialize() async {
    _updateCallState(CallState.idle);
  }
  
  // 통화 상태 업데이트
  void _updateCallState(CallState newState) {
    _currentCallState = newState;
    _callStateController.add(newState);
  }

  // 통화 시작
  Future<void> startCall(List<String> participants) async {
    if (_currentCallState != CallState.idle) return;
    
    _updateCallState(CallState.connecting);
    
    try {
      // WebRTC 설정 (STUN/TURN 서버 등)
      Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
        ]
      };
      
      // 미디어 제약조건
      final Map<String, dynamic> constraints = {
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480}
        }
      };
      
      // PeerConnection 생성
      _peerConnection = await createPeerConnection(configuration);
      
      // 로컬 미디어 스트림 설정
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      // RTCVideoRenderer 설정 (UI 표시용)
      RTCVideoRenderer localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      localRenderer.srcObject = _localStream;
      _localRendererController.add(localRenderer);
      
      // 로컬 트랙 추가
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      // 원격 트랙 이벤트 처리
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          
          // RTCVideoRenderer 설정 (UI 표시용)
          RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
          remoteRenderer.initialize().then((_) {
            remoteRenderer.srcObject = _remoteStream;
            _remoteRendererController.add(remoteRenderer);
          });
        }
      };
      
      // 기타 WebRTC 이벤트 핸들러
      _peerConnection!.onIceCandidate = (candidate) {
        // 실제 앱에서는 시그널링 서버를 통해 상대방에게 candidate 전송
        print('ICE 후보 생성됨: ${candidate.toMap()}');
      };
      
      _peerConnection!.onConnectionState = (state) {
        print('연결 상태 변경: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateCallState(CallState.connected);
        }
      };
      
      // 시그널링 서버를 통한 Offer/Answer 교환 로직은 앱 구현에 맞게 별도 추가 필요
      // createOffer, setLocalDescription, sendOffer 등의 과정
      
      // 여기서는 통화가 바로 연결된 것으로 시뮬레이션 (실제 앱에서는 시그널링 과정 필요)
      _callStartTime = DateTime.now();
      
      // Firestore에 대화 기록 생성
      if (_currentConversationId == null) {
        _currentConversationId = await _storageService.createConversation(
          participants, 
          _callStartTime!
        );
      }
      
      if (_currentConversationId != null) {
        // 녹음 시작
        await _audioRecordingService.startRecording(_currentConversationId!);
        print('통화 시작 및 녹음 시작됨 (대화 ID: $_currentConversationId)');
      } else {
        print('Firestore에 대화 문서 생성 실패');
      }
      
      _updateCallState(CallState.connected);
    } catch (e) {
      print('통화 시작 중 오류 발생: $e');
      _updateCallState(CallState.error);
    }
  }

  // 통화 종료
  Future<void> endCall() async {
    if (_currentCallState != CallState.connected) return;
    
    _updateCallState(CallState.disconnecting);
    
    final callEndTime = DateTime.now();
    final conversationId = _currentConversationId;
    
    try {
      // 녹음 중지 및 파일 경로 얻기
      final audioFilePath = await _audioRecordingService.stopRecording();
      print('녹음 중지됨. 오디오 파일 경로: $audioFilePath');
      
      // Firestore에 통화 종료 정보 업데이트
      if (conversationId != null) {
        await _storageService.updateConversationOnEnd(
          conversationId, 
          callEndTime, 
          audioFilePath
        );
      }
      
      // WebRTC 연결 종료
      _localStream?.getTracks().forEach((track) => track.stop());
      _remoteStream?.getTracks().forEach((track) => track.stop());
      await _peerConnection?.close();
      _peerConnection = null;
      _localStream = null;
      _remoteStream = null;
      
      // 상태 초기화
      _currentConversationId = null;
      _callStartTime = null;
      
      _updateCallState(CallState.idle);
      
      // 백그라운드 처리 시작
      if (audioFilePath != null && conversationId != null) {
        print('백그라운드 처리 시작 (대화 ID: $conversationId)');
        
        // Isolate를 사용하여 백그라운드에서 처리
        // _processConversationInBackground({'conversationId': conversationId, 'audioFilePath': audioFilePath});
        // 메인 스레드에서 실행 (데모 목적. 실제로는 Isolate 사용 권장)
        await _processConversationInBackground({
          'conversationId': conversationId, 
          'audioFilePath': audioFilePath
        });
      }
    } catch (e) {
      print('통화 종료 중 오류 발생: $e');
      _updateCallState(CallState.error);
    }
  }

  // 백그라운드 처리 (Whisper API 및 GPT API 호출)
  Future<void> _processConversationInBackground(Map<String, String> args) async {
    final conversationId = args['conversationId']!;
    final audioFilePath = args['audioFilePath']!;
    
    try {
      // 1. Whisper로 스크립트 변환
      print('오디오 변환 중 (대화 ID: $conversationId)...');
      final script = await _whisperService.transcribe(audioFilePath);
      
      if (script != null) {
        // 2. 스크립트 저장
        print('스크립트 저장 중 (대화 ID: $conversationId)...');
        await _storageService.saveScript(conversationId, script);
        
        // 3. GPT 분석 요청
        print('스크립트 분석 중 (대화 ID: $conversationId)...');
        final analysis = await _gptService.analyze(script);
        
        if (analysis != null) {
          // 4. 분석 결과 저장
          print('분석 결과 저장 중 (대화 ID: $conversationId)...');
          await _storageService.saveAnalysis(conversationId, analysis);
          print('백그라운드 처리 완료 (대화 ID: $conversationId)');
        } else {
          print('GPT 분석 실패 (대화 ID: $conversationId)');
        }
      } else {
        print('오디오 변환 실패 (대화 ID: $conversationId)');
      }
    } catch (e) {
      print('백그라운드 처리 중 오류 발생: $e');
    }
  }

  // 리소스 해제
  Future<void> dispose() async {
    // 통화 중이라면 종료
    if (_currentCallState == CallState.connected) {
      await endCall();
    }
    
    // 스트림 컨트롤러 정리
    await _localRendererController.close();
    await _remoteRendererController.close();
    await _callStateController.close();
    
    // 서비스 정리
    await _audioRecordingService.dispose();
  }
}

// 통화 상태 열거형
enum CallState {
  idle,         // 통화 대기 중
  connecting,   // 연결 시도 중
  connected,    // 통화 중
  disconnecting, // 연결 종료 중
  error         // 오류 발생
}