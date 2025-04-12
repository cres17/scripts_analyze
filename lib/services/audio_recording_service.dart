import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class AudioRecordingService {
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;
  bool _isRecording = false;

  /// 녹음 시작 함수
  Future<void> startRecording(String conversationId) async {
    if (_isRecording) return;

    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        debugPrint('마이크 권한이 거부되었습니다.');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${directory.path}/audio_records');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      _recordingPath = '${recordingsDir.path}/${conversationId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
        debugPrint('녹음이 시작되었습니다: $_recordingPath');
      } else {
        debugPrint('녹음기 권한이 없습니다.');
      }
    } catch (e) {
      debugPrint('녹음 시작 중 오류 발생: $e');
    }
  }

  /// 녹음 중지 함수
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      debugPrint('녹음이 중지되었습니다: $path');

      final file = File(path!);
      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('녹음 파일 크기: ${fileSize ~/ 1024} KB');
        return path;
      } else {
        debugPrint('녹음 파일이 존재하지 않습니다.');
        return null;
      }
    } catch (e) {
      debugPrint('녹음 중지 중 오류 발생: $e');
      _isRecording = false;
      return null;
    }
  }

  /// 리소스 해제
  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }

  /// 상태 확인
  bool get isRecording => _isRecording;
}
