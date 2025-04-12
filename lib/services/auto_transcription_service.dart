// ✅ 이 클래스는 영상통화 시작 시 자동 녹음 → Whisper API 호출 → 스크립트 저장 → 파일 삭제를 처리합니다.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_recording_service.dart';
import 'whisper_service.dart';
import 'storage_service.dart';

class AutoTranscriptionService {
  final AudioRecordingService _audioRecorder = AudioRecordingService();
  final WhisperService _whisperService = WhisperService();
  final StorageService _storageService = StorageService();

  // 자동 녹음 + 스크립트 변환 + 저장까지 수행
  Future<void> handleRecordingAndTranscription({
    required String conversationId,
  }) async {
    try {
      debugPrint('[자동전사] 녹음 시작 중...');
      await _audioRecorder.startRecording(conversationId);
    } catch (e) {
      debugPrint('[자동전사] 녹음 시작 실패: $e');
    }
  }

  Future<void> stopAndProcessRecording({
    required String conversationId,
  }) async {
    try {
      debugPrint('[자동전사] 녹음 중지 중...');
      final path = await _audioRecorder.stopRecording();
      if (path == null) {
        debugPrint('[자동전사] 녹음 파일 없음');
        return;
      }

      debugPrint('[자동전사] Whisper API 호출 시작...');
      final script = await _whisperService.transcribe(path);
      if (script == null) {
        debugPrint('[자동전사] Whisper 스크립트 변환 실패');
        return;
      }

      debugPrint('[자동전사] Firestore에 스크립트 저장 중...');
      await _storageService.saveScript(conversationId, script);

      // 파일 삭제
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[자동전사] 녹음 파일 삭제 완료');
      }
    } catch (e) {
      debugPrint('[자동전사] 처리 중 오류 발생: $e');
    }
  }

  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }
}
