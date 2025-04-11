import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../services/call_service.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _isConnecting = true;

  @override
  void initState() {
    super.initState();
    final callService = Provider.of<CallService>(context, listen: false);

    // 자동 연결 시도
    callService.localRendererStream.listen((renderer) {
      setState(() {
        _localRenderer = renderer;
        _isConnecting = false;
      });
    });

    callService.remoteRendererStream.listen((renderer) {
      setState(() {
        _remoteRenderer = renderer;
      });
    });

    // 🔽 자동 연결 (callee일 경우 joinCall, caller일 경우 createCall)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callService.autoConnect(); // 위에서 만든 createCall/joinCall 자동 호출 함수
    });
  }

  @override
  Widget build(BuildContext context) {
    final callService = Provider.of<CallService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text("영상통화"),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end),
            onPressed: () async {
              await callService.endCall();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _remoteRenderer != null
                ? RTCVideoView(
                    _remoteRenderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : const Center(child: Text("상대방을 기다리는 중...")),
          ),
          SizedBox(
            height: 200,
            child: _localRenderer != null
                ? RTCVideoView(
                    _localRenderer!,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          if (_isConnecting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("통화 연결 중...", style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }
}
