import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_firestore/firebase_firestore.dart';
import 'package:flutter/foundation.dart';

class AudioRecordingService {
  // 이렇게 사용하면 됩니다
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;
  bool _isRecording = false;
  bool _isProcessingConnection = false;
  bool _isProcessingJoin = false;

  // 녹음 시작 함수
  Future<void> startRecording(String conversationId) async {
    if (_isRecording) return;

    try {
      // 마이크 권한 요청
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('마이크 권한이 거부되었습니다.');
        return;
      }

      // 녹음 파일 경로 설정
      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/audio_records');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      
      _recordingPath = '${recordingsDir.path}/${conversationId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // 녹음 시작
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _recordingPath!,
        );
        _isRecording = true;
        print('녹음이 시작되었습니다: $_recordingPath');
      } else {
        print('녹음기 권한이 없습니다.');
      }
    } catch (e) {
      print('녹음 시작 중 오류 발생: $e');
    }
  }

  // 나머지 코드는 동일


  // 녹음 중지 함수
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      // 녹음 중지
      final path = await _audioRecorder.stop();
      _isRecording = false;
      print('녹음이 중지되었습니다: $path');
      
      // 파일 존재 확인
      final file = File(path!);
      if (await file.exists()) {
        final fileSize = await file.length();
        print('녹음 파일 크기: ${fileSize ~/ 1024} KB');
        return path;
      } else {
        print('녹음 파일이 존재하지 않습니다.');
        return null;
      }
    } catch (e) {
      print('녹음 중지 중 오류 발생: $e');
      _isRecording = false;
      return null;
    }
  }

  // 리소스 해제 함수
  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }

  // 녹음 상태 확인 함수
  bool get isRecording => _isRecording;

  void _listenForWaitingUsers() {
    _waitingRoomSubscription?.cancel();
    
    _waitingRoomSubscription = FirebaseFirestore.instance
        .collection('waiting_users')
        .orderBy('timestamp')
        .limit(10)
        .snapshots()
        .listen((snapshot) async {
      if (_isInCall || _isProcessingConnection) return;
      
      // 대기 중인 사용자들
      final waitingUsers = snapshot.docs.where((doc) => doc.id != currentUserId).toList();
      
      if (waitingUsers.isNotEmpty) {
        // 중복 처리 방지
        _isProcessingConnection = true;
        
        try {
          // 기존 피어 연결 정리
          if (_peerConnection != null) {
            await _peerConnection!.close();
            _peerConnection = null;
          }
          
          // 새 연결 시작
          final oldestWaitingUser = waitingUsers.first;
          await createCall(oldestWaitingUser.id);
        } catch (e) {
          debugPrint('연결 시도 오류: $e');
        } finally {
          _isProcessingConnection = false;
        }
      }
    });
  }

  void listenForCalls() {
    FirebaseFirestore.instance
        .collection('user_calls')
        .doc(currentUserId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists || doc.data() == null || _isProcessingJoin) return;
      
      _isProcessingJoin = true;
      try {
        final data = doc.data()!;
        // ... 기존 코드 ...
      } finally {
        _isProcessingJoin = false;
      }
    });
  }

  // 초대 문서 삭제
  Future<void> deleteCall() async {
    await FirebaseFirestore.instance
        .collection('user_calls')
        .doc(currentUserId)
        .delete();
  }
}