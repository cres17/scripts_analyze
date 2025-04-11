import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/call_service.dart';
import 'ui/video_call_screen.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // ✅ Firebase 익명 로그인 시도
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    debugPrint('Firebase Auth Error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final service = CallService();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          service.listenForMatchedRoom(uid); // 상대방이 나를 콜할 경우 대비
        }
        return service;
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'WebRTC Video Call',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
