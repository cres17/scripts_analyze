import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/call_service.dart';
import 'ui/video_call_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // Firebase 인증 익명 로그인
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CallService()..listenForMatchedRoom(FirebaseAuth.instance.currentUser!.uid),
      child: MaterialApp(
        title: 'WebRTC Video Call',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const VideoCallScreen(),
      ),
    );
  }
}
