// lib/ui/video_call_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _localRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = stream;
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("영상통화")),
      body: Center(
        child: RTCVideoView(_localRenderer),
      ),
    );
  }
}
