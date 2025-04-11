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
      appBar: AppBar(title: const Text('대화 기록')),
      body: StreamBuilder<List<Conversation>>(
        stream: _storageService.getConversationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingView();
          }

          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error.toString());
          }

          final conversations = snapshot.data ?? [];

          if (conversations.isEmpty) {
            return const _EmptyView();
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conv = conversations[index];

              final matchingProbability = conv.gptAnalysis?['matching_probability'];
              final matchingValue = (matchingProbability is num) ? matchingProbability.toInt() : null;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text('대화 ${index + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('참여자: ${conv.participants.join(', ')}'),
                      Text('시작: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.startTime)}'),
                      if (conv.endTime != null)
                        Text('종료: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.endTime!)}'),
                      if (conv.whisperScript != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('스크립트: 변환 완료', style: TextStyle(color: Colors.green)),
                        ),
                      if (matchingValue != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Text('매칭 확률: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                '$matchingValue%',
                                style: TextStyle(
                                  color: _getMatchingProbabilityColor(matchingValue),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConversationDetailScreen(conversationId: conv.id),
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

  static Color _getMatchingProbabilityColor(int value) {
    if (value >= 80) return Colors.green;
    if (value >= 50) return Colors.orange;
    return Colors.red;
  }
}

// --- UI 상태 위젯들 (재사용 가능) ---

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('대화 기록이 없습니다.'));
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('오류 발생: $error'));
  }
}
