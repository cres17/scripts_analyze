import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/call_service.dart';
import 'video_call_screen.dart';
import 'history_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 테스트용 상대방 UID 필드
  String _targetUserId = '';
  TextEditingController _targetUserController = TextEditingController();
  bool _isLoadingUsers = false;
  List<Map<String, dynamic>> _onlineUsers = [];
  
  @override
  void initState() {
    super.initState();
    
    // 기본값으로 "test_user" 설정
    _targetUserController.text = "test_user";
    _targetUserId = _targetUserController.text;

    final callService = Provider.of<CallService>(context, listen: false);
    callService.init();

    callService.incomingCallStream.listen((data) {
      final callId = data['callId']!;
      final callerId = data['callerId']!;
      print('수신 통화 알림 받음: $callerId 로부터');
      _showIncomingCallDialog(callId, callerId);
    });
    
    // 온라인 사용자 목록 구독
    callService.onlineUsersStream.listen((users) {
      setState(() {
        _onlineUsers = users;
        _isLoadingUsers = false;
      });
    });
    
    // 초기 사용자 목록 로드
    _loadOnlineUsers();
  }
  
  Future<void> _loadOnlineUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });
    
    try {
      final callService = Provider.of<CallService>(context, listen: false);
      await callService.getOnlineUsers(); 
      // 결과는 스트림을 통해 받습니다
    } catch (e) {
      print('온라인 사용자 로드 오류: $e');
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  @override
  void dispose() {
    _targetUserController.dispose();
    super.dispose();
  }

  void _showIncomingCallDialog(String callId, String callerId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('수신 통화'),
        content: Text('$callerId 님으로부터 수신된 통화입니다.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Provider.of<CallService>(context, listen: false).declineCall(callId);
            },
            child: const Text('거절'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Provider.of<CallService>(context, listen: false).acceptCall(callId);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoCallScreen()));
            },
            child: const Text('수락'),
          ),
        ],
      ),
    );
  }
  
  // 사용자 선택 다이얼로그 표시
  void _showUserSelectionDialog() {
    setState(() {
      _isLoadingUsers = true;
    });
    
    // 먼저 사용자 목록 새로고침
    final callService = Provider.of<CallService>(context, listen: false);
    callService.getOnlineUsers().then((users) {
      setState(() {
        _isLoadingUsers = false;
        _onlineUsers = users;
      });
      
      // 사용자 목록 다이얼로그 표시
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Text('대화 상대 선택'),
              const Spacer(),
              if (_isLoadingUsers)
                const SizedBox(
                  width: 20,
                  height: 20, 
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          content: _onlineUsers.isEmpty
              ? const Text('현재 온라인 사용자가 없습니다.\n새로고침 버튼을 눌러 다시 시도해보세요.')
              : SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    itemCount: _onlineUsers.length,
                    itemBuilder: (context, index) {
                      final user = _onlineUsers[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(user['displayName'].toString().substring(0, 1)),
                          ),
                          title: Text(user['displayName']),
                          subtitle: Text('ID: ${user['userId']}'),
                          trailing: const Icon(Icons.call),
                          onTap: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _targetUserId = user['userId'];
                              _targetUserController.text = user['userId'];
                            });
                            
                            // 바로 통화 걸기 옵션 다이얼로그
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('통화 연결'),
                                content: Text('${user['displayName']}님에게 바로 영상통화를 걸까요?'),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('아니오'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      _startCall();
                                    },
                                    child: const Text('예'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('취소'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('새로고침'),
              onPressed: () {
                setState(() {
                  _isLoadingUsers = true;
                });
                Navigator.of(context).pop();
                _loadOnlineUsers().then((_) {
                  // 목록 새로고침 후 다시 다이얼로그 표시
                  _showUserSelectionDialog();
                });
              },
            ),
          ],
        ),
      );
    });
  }
  
  // 통화 시작 함수
  void _startCall() async {
    if (_targetUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상대방 ID를 입력하거나 선택하세요')),
      );
      return;
    }
    
    final callService = Provider.of<CallService>(context, listen: false);
    try {
      await callService.createCall(_targetUserId);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VideoCallScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('통화 연결 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '익명';
    
    return Scaffold(
      appBar: AppBar(title: const Text('소개팅 홈')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('현재 사용자: $currentUserId', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            
            // 온라인 사용자 수
            _isLoadingUsers
                ? const CircularProgressIndicator()
                : Text(
                    '온라인 사용자: ${_onlineUsers.length}명',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
            const SizedBox(height: 10),
            
            // 사용자 선택 버튼
            ElevatedButton.icon(
              icon: const Icon(Icons.people),
              label: const Text('대화 상대 선택'),
              onPressed: _showUserSelectionDialog,
            ),
            
            const SizedBox(height: 20),
            
            // 수동 입력 필드도 유지
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: TextField(
                controller: _targetUserController,
                decoration: const InputDecoration(
                  labelText: '상대방 ID',
                  hintText: '통화할 상대방 ID 입력',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _targetUserId = value;
                  });
                },
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 영상통화 시작 버튼
            ElevatedButton.icon(
              icon: const Icon(Icons.video_call),
              label: const Text('영상통화 시작'),
              onPressed: _startCall,
            ),
            const SizedBox(height: 20),
            
            // 히스토리 버튼
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('히스토리'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HistoryScreen()),
                );
              },
            ),
          ],
        ),
      ),
      // 새로고침 버튼 추가
      floatingActionButton: FloatingActionButton(
        onPressed: _loadOnlineUsers,
        tooltip: '사용자 목록 새로고침',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
