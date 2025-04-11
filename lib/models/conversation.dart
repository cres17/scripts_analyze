import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id; // Firestore Document ID
  final List<String> participants; // 참여자 ID 또는 이름 목록
  final DateTime startTime; // 통화 시작 시간
  final DateTime? endTime;   // 통화 종료 시간
  final String? audioFilePath; // 녹음 파일 로컬 경로
  final String? whisperScript; // Whisper 변환 스크립트
  final Map<String, dynamic>? gptAnalysis; // GPT 분석 결과
  final Timestamp createdAt; // 생성 시간 (Firestore 타임스탬프)

  Conversation({
    required this.id,
    required this.participants,
    required this.startTime,
    this.endTime,
    this.audioFilePath,
    this.whisperScript,
    this.gptAnalysis,
    required this.createdAt,
  });

  Conversation copyWith({
    String? id,
    List<String>? participants,
    DateTime? startTime,
    DateTime? endTime,
    String? audioFilePath,
    String? whisperScript,
    Map<String, dynamic>? gptAnalysis,
    Timestamp? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      whisperScript: whisperScript ?? this.whisperScript,
      gptAnalysis: gptAnalysis ?? this.gptAnalysis,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  
  // Firestore 데이터를 Conversation 객체로 변환
  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: data['endTime'] != null ? (data['endTime'] as Timestamp).toDate() : null,
      audioFilePath: data['audioFilePath'],
      whisperScript: data['whisperScript'],
      gptAnalysis: data['gptAnalysis'],
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  // Conversation 객체를 Firestore 데이터로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'participants': participants,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'audioFilePath': audioFilePath,
      'whisperScript': whisperScript,
      'gptAnalysis': gptAnalysis,
      'createdAt': createdAt,
    };
  }
}