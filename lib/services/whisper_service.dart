import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WhisperService {
  // .env 파일에서 API 키 로드
  final String _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  final String _apiUrl = 'https://api.openai.com/v1/audio/transcriptions';

  // 오디오 파일을 텍스트로 변환하는 함수
  Future<String?> transcribe(String audioFilePath) async {
    if (_apiKey.isEmpty) {
      print('OpenAI API 키가 .env 파일에 설정되지 않았습니다.');
      return null;
    }

    try {
      // 파일 존재 확인
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        print('오디오 파일이 존재하지 않습니다: $audioFilePath');
        return null;
      }

      // 멀티파트 요청 생성
      var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.headers['Authorization'] = 'Bearer $_apiKey';
      
      // 파일 첨부
      request.files.add(await http.MultipartFile.fromPath('file', audioFilePath));
      
      // 파라미터 설정
      request.fields['model'] = 'whisper-1'; // Whisper 모델 지정
      request.fields['language'] = 'ko'; // 한국어 지정 (선택사항)
      request.fields['response_format'] = 'json'; // JSON 응답 형식 지정
      
      print('Whisper API 요청 전송 중...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var responseData = jsonDecode(utf8.decode(response.bodyBytes));
        print('Whisper API 응답: ${responseData['text']}');

        // TODO: 발화자 구분 처리 (현재 API에서 지원하지 않음)
        // 간단한 발화자 구분 시뮬레이션 (실제 구현에서는 더 정교한 방법 필요)
        String rawText = responseData['text'];
        String formattedText = _simulateSpeakerDiarization(rawText);
        
        return formattedText;
      } else {
        print('Whisper API 오류: ${response.statusCode}');
        print('응답 내용: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Whisper API 호출 중 오류 발생: $e');
      return null;
    }
  }
  
  // 발화자 구분 시뮬레이션 (실제 구현에서는 더 정교한 방법 필요)
  String _simulateSpeakerDiarization(String text) {
    List<String> sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    bool isUserA = true;
    List<String> diarizedText = [];
    
    for (var sentence in sentences) {
      if (sentence.trim().isNotEmpty) {
        diarizedText.add('${isUserA ? "A" : "B"}: $sentence');
        isUserA = !isUserA; // 간단한 번갈아가며 발화자 전환
      }
    }
    
    return diarizedText.join('\n');
  }
}