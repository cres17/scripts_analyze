import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GptService {
  // .env 파일에서 API 키 로드
  final String _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  final String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  // 스크립트 분석 함수
  Future<Map<String, dynamic>?> analyze(String script) async {
    if (_apiKey.isEmpty) {
      print('OpenAI API 키가 .env 파일에 설정되지 않았습니다.');
      return null;
    }

    // GPT 분석용 프롬프트 구성
    String prompt = """
다음은 두 사람 간의 영상통화 대화 내용입니다. ${script.contains('A:') ? '각 발화는 A와 B로 구분되어 있습니다.' : ''}

이 대화를 아래 기준에 따라 JSON 형식으로 분석해주세요:
1.  **cooperation_principles**: Grice의 협력 원리(양, 질, 관련성, 명확성) 준수 여부 및 근거 (간략히)
2.  **reciprocity**: 상호 호혜적 의사소통이 이루어졌는지 여부 및 근거 (간략히)
3.  **self_disclosure**: 자아 노출 수준과 상대방과의 적절한 거리 유지 여부 (간략히)
4.  **listening_cooperation**: 경청 및 협력적 반응이 나타나는지 여부 및 근거 (간략히)
5.  **politeness**: 공손성 유지 여부 (간략히)
6.  **matching_probability**: 연애 예능 '나는 솔로' 컨셉의 매칭 확률 예측 (0부터 100 사이의 정수 숫자만)

분석 결과는 반드시 아래와 같은 JSON 형식으로 반환해주세요:
{
  "cooperation_principles": {"summary": "분석 내용", "evidence": ["근거1", "근거2"]},
  "reciprocity": {"summary": "분석 내용", "evidence": ["근거1"]},
  "self_disclosure": {"summary": "분석 내용"},
  "listening_cooperation": {"summary": "분석 내용", "evidence": ["근거1"]},
  "politeness": {"summary": "분석 내용"},
  "matching_probability": 85
}

--- 대화 내용 시작 ---
$script
--- 대화 내용 끝 ---
""";

    try {
      // GPT API 호출
      var response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o', // 또는 적절한 GPT 모델
          'messages': [
            {'role': 'system', 'content': 'You are a helpful assistant that analyzes conversations according to specific criteria and returns the result in JSON format.'},
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7, // 창의성 조절
          'response_format': { 'type': 'json_object' } // JSON 응답 형식 강제
        }),
      );

      // 응답 처리
      if (response.statusCode == 200) {
        var responseData = jsonDecode(utf8.decode(response.bodyBytes));
        String jsonString = responseData['choices'][0]['message']['content'];
        print('GPT API 원본 응답: $jsonString');

        // JSON 파싱
        try {
          Map<String, dynamic> analysisResult = jsonDecode(jsonString);
          print('GPT 분석 결과 (파싱됨): $analysisResult');
          return analysisResult;
        } catch (e) {
           print('GPT JSON 응답 파싱 오류: $e');
           // JSON 파싱 실패 시 처리
           return {'error': 'GPT 응답 파싱 실패', 'raw_response': jsonString};
        }
      } else {
        print('GPT API 오류: ${response.statusCode}');
        print('응답 내용: ${response.body}');
        return null;
      }
    } catch (e) {
      print('GPT API 호출 중 오류 발생: $e');
      return null;
    }
  }
}