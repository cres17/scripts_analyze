import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import '../models/conversation.dart';
import 'conversation_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  final StorageService _storageService = StorageService();

  HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('대화 기록'),
      ),
      body: StreamBuilder<List<Conversation>>(
        stream: _storageService.getConversationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('오류 발생: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('대화 기록이 없습니다.'));
          }

          final conversations = snapshot.data!;

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conv = conversations[index];
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text('대화 ${index + 1}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('참여자: ${conv.participants.join(', ')}'),
                      Text('시작: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.startTime)}'),
                      if (conv.endTime != null)
                        Text('종료: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.endTime!)}'),
                      if (conv.whisperScript != null)
                        const Text('스크립트: 변환 완료', style: TextStyle(color: Colors.green)),
                      if (conv.gptAnalysis != null)
                        Row(
                          children: [
                            const Text('매칭 확률: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              '${conv.gptAnalysis!['matching_probability'] ?? '분석 중'}%',
                              style: TextStyle(
                                color: _getMatchingProbabilityColor(
                                  conv.gptAnalysis!['matching_probability'] as int? ?? 0
                                ),
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConversationDetailScreen(
                          conversationId: conv.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
  
  // 매칭 확률에 따른 색상 반환
  Color _getMatchingProbabilityColor(int probability) {
    if (probability >= 80) return Colors.green;
    if (probability >= 50) return Colors.orange;
    return Colors.red;
  }
}