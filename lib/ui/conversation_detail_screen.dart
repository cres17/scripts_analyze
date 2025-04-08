import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../models/conversation.dart';
import 'package:intl/intl.dart';

class ConversationDetailScreen extends StatefulWidget {
  final String conversationId;

  const ConversationDetailScreen({super.key, required this.conversationId});

  @override
  State<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  Future<Conversation?>? _conversationFuture;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _conversationFuture = _storageService.getConversationDetail(widget.conversationId);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('대화 상세 (ID: ${widget.conversationId.substring(0, 6)}...)'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '대화 스크립트'),
            Tab(text: 'GPT 분석 결과'),
          ],
        ),
      ),
      body: FutureBuilder<Conversation?>(
        future: _conversationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('오류 발생: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('대화 정보를 불러올 수 없습니다.'));
          }

          final conv = snapshot.data!;
          
          // 스크립트나 분석 결과가 아직 없는 경우 표시
          if (conv.whisperScript == null && conv.gptAnalysis == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('대화 처리 중입니다. 잠시 후 다시 확인해주세요.'),
                ],
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // 스크립트 탭
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(conv),
                    const SizedBox(height: 16),
                    const Text('대화 스크립트:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: conv.whisperScript != null
                          ? Text(conv.whisperScript!)
                          : const Text('스크립트가 생성되지 않았습니다.'),
                    ),
                  ],
                ),
              ),
              
              // 분석 결과 탭
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(conv),
                    const SizedBox(height: 16),
                    const Text('GPT 분석 결과:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    conv.gptAnalysis != null
                        ? _buildAnalysisView(conv.gptAnalysis!)
                        : Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('분석 결과가 아직 없습니다.'),
                          ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // 정보 카드 위젯
  Widget _buildInfoCard(Conversation conv) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('참여자: ${conv.participants.join(", ")}'),
            const SizedBox(height: 4),
            Text('시작: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.startTime)}'),
            if (conv.endTime != null)
              Text('종료: ${DateFormat('yyyy-MM-dd HH:mm').format(conv.endTime!)}'),
          ],
        ),
      ),
    );
  }
  
  // 분석 결과 위젯
  Widget _buildAnalysisView(Map<String, dynamic> analysis) {
    // GPT 응답 형식에 맞춰 각 항목 표시
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: analysis.entries.map((entry) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatAnalysisKey(entry.key), 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (entry.value is Map)
                  ..._buildMapValueContent(entry.value)
                else
                  Text(entry.value.toString()),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
  
  // 맵 형태의 분석 결과 표시
  List<Widget> _buildMapValueContent(Map<String, dynamic> value) {
    List<Widget> widgets = [];
    
    if (value.containsKey('summary')) {
      widgets.add(
        Text('요약: ${value['summary']}', 
             style: const TextStyle(fontSize: 14)),
      );
    }
    
    if (value.containsKey('evidence') && value['evidence'] is List && (value['evidence'] as List).isNotEmpty) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Text('근거:', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      );
      
      List evidence = value['evidence'] as List;
      for (var item in evidence) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
            child: Text('• $item', style: const TextStyle(fontSize: 14)),
          ),
        );
      }
    }
    
    return widgets;
  }
  
  // 분석 키를 한글로 변환
  String _formatAnalysisKey(String key) {
    switch (key) {
      case 'cooperation_principles': return '협력 원리';
      case 'reciprocity': return '상호 호혜성';
      case 'self_disclosure': return '자아 노출';
      case 'listening_cooperation': return '경청 및 협력';
      case 'politeness': return '공손성';
      case 'matching_probability': return '매칭 확률 (%)';
      default: return key;
    }
  }
}