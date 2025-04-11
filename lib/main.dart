import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'services/call_service.dart';
import 'ui/home_screen.dart';
import 'firebase_options.dart';

// CallService 인스턴스를 앱 전체에서 접근할 수 있도록 글로벌 변수로 선언
final CallService callService = CallService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  await Firebase.initializeApp();
  
  // 환경 변수 파일 로드 시도 (.env가 없어도 오류 무시)
  try {
    await dotenv.load(fileName: ".env"); 
    debugPrint('.env 파일 로드 성공');
  } catch (e) {
    debugPrint('.env 파일 로드 실패: $e - 기본값 사용');
    // .env 파일이 없는 경우를 위한 기본값 설정
    dotenv.env['OPENAI_API_KEY'] = 'sk-your-api-key-here';
  }
  
  // 테스트를 위한 익명 로그인
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    try {
      final userCredential = await auth.signInAnonymously();
      final user = userCredential.user;
      debugPrint('익명 로그인 성공: ${user?.uid}');
    } catch (e) {
      debugPrint('익명 로그인 실패: $e');
    }
  } else {
    debugPrint('이미 로그인된 사용자: ${auth.currentUser?.uid}');
  }
  
  // 앱 종료 시 CallService 정리
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('앱 오류 발생: $error');
    // 오류가 발생해도 callService를 정리
    callService.disposeService();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: callService, // 전역 인스턴스 사용
      child: MaterialApp(
        title: '소개팅 영상통화',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
