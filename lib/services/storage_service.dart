import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation.dart';
import 'gpt_service.dart'; // GPT 서비스 import 추가

class StorageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionName = 'conversations';

  final GptService _gptService = GptService(); // GPT 서비스 인스턴스

  Future<String?> createConversation(List<String> participants, DateTime startTime) async {
    try {
      DocumentReference docRef = await _db.collection(_collectionName).add({
        'participants': participants,
        'startTime': Timestamp.fromDate(startTime),
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('대화 문서 생성됨. ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('대화 문서 생성 중 오류 발생: $e');
      return null;
    }
  }

  Future<void> updateConversationOnEnd(String conversationId, DateTime endTime, String? audioFilePath) async {
    try {
      await _db.collection(_collectionName).doc(conversationId).update({
        'endTime': Timestamp.fromDate(endTime),
        'audioFilePath': audioFilePath,
      });
      print('대화 ID $conversationId 종료 정보 업데이트됨.');
    } catch (e) {
      print('대화 종료 정보 업데이트 중 오류 발생: $e');
    }
  }

  Future<void> saveScript(String conversationId, String script) async {
    try {
      await _db.collection(_collectionName).doc(conversationId).update({
        'whisperScript': script,
      });
      print('대화 ID $conversationId의 스크립트 저장됨.');
    } catch (e) {
      print('스크립트 저장 중 오류 발생: $e');
    }
  }

  Future<void> saveAnalysis(String conversationId, Map<String, dynamic> analysis) async {
    try {
      await _db.collection(_collectionName).doc(conversationId).update({
        'gptAnalysis': analysis,
      });
      print('대화 ID $conversationId의 분석 결과 저장됨.');
    } catch (e) {
      print('분석 결과 저장 중 오류 발생: $e');
    }
  }

  Stream<List<Conversation>> getConversationsStream() {
    return _db.collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Conversation.fromFirestore(doc))
            .toList())
        .handleError((error) {
          print("대화 목록 조회 중 오류 발생: $error");
          return [];
        });
  }

  Future<Conversation?> getConversationDetail(String conversationId) async {
    try {
      DocumentSnapshot doc = await _db.collection(_collectionName).doc(conversationId).get();
      if (doc.exists) {
        return Conversation.fromFirestore(doc);
      } else {
        print('대화 ID $conversationId에 해당하는 문서가 없습니다.');
        return null;
      }
    } catch (e) {
      print('대화 상세 정보 조회 중 오류 발생: $e');
      return null;
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await _db.collection(_collectionName).doc(conversationId).delete();
      print('대화 ID $conversationId 삭제됨.');
    } catch (e) {
      print('대화 삭제 중 오류 발생: $e');
    }
  }

  /// ✅ GPT 분석 통합 메서드
  Future<Conversation?> analyzeConversationWithGPT(Conversation conv) async {
    if (conv.whisperScript == null || conv.whisperScript!.trim().isEmpty) {
      throw Exception('스크립트가 존재하지 않습니다.');
    }

    try {
      final analysis = await _gptService.analyze(conv.whisperScript!);
      if (analysis == null) throw Exception('GPT 분석 결과 없음');

      await saveAnalysis(conv.id, analysis);
      return conv.copyWith(gptAnalysis: analysis);
    } catch (e) {
      print('GPT 분석 실패: $e');
      rethrow;
    }
  }
}
