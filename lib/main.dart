import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'services/call_service.dart';
import 'ui/history_screen.dart';
import 'ui/video_call_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // .env 파일 로드
  await dotenv.load(fileName: ".env");
  
  // Firebase 초기화
  await Firebase.initializeApp();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<CallService>(
      create: (_) => CallService(),
      dispose: (_, service) => service.dispose(),
      child: MaterialApp(
        title: '영상통화 분석 앱',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CallService _callService;
  late StreamSubscription _callStateSubscription;

  @override
  void initState() {
    super.initState();
    _callService = Provider.of<CallService>(context, listen: false);

    _callStateSubscription = _callService.callStateStream.listen((state) {
      if (state == CallState.connected) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const VideoCallScreen(),
          ),
        );
      }
      if (state == CallState.idle) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // 영상통화 화면 닫기
        }
      }
    });
  }

  @override
  void dispose() {
    _callStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('영상통화 분석 앱'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryScreen(),
                  ),
                );
              },
              child: const Text('대화 기록 보기'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _callService.startCall(['User1', 'User2']); // context 인자 제거!
              },
              child: const Text('통화 시작'),
            ),
          ],
        ),
      ),
    );
  }
}