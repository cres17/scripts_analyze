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
  bool _isMuted = false;
  bool _isCameraOff = false;

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
      _setupConnection();
    });
  }

  void _setupConnection() {
    final callService = Provider.of<CallService>(context, listen: false);
    callService.autoConnect().catchError((error) {
      // 연결 실패시 재시도 버튼 표시
      setState(() {
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('연결 실패: ${error.toString()}'),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () {
              setState(() {
                _isConnecting = true;
              });
              _setupConnection();
            },
          ),
        ),
      );
    });
  }

  void _toggleMute() {
    final callService = Provider.of<CallService>(context, listen: false);
    final isMuted = callService.toggleAudio();
    setState(() {
      _isMuted = !isMuted;  // toggleAudio는 활성화 여부를 반환하므로 반전시켜서 사용
    });
  }

  void _toggleCamera() {
    final callService = Provider.of<CallService>(context, listen: false);
    final isVideoEnabled = callService.toggleVideo();
    setState(() {
      _isCameraOff = !isVideoEnabled;  // toggleVideo는 활성화 여부를 반환하므로 반전시켜서 사용
    });
  }

  void _switchCamera() {
    final callService = Provider.of<CallService>(context, listen: false);
    callService.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    final callService = Provider.of<CallService>(context);

    // 연결 오류 발생시 재연결 화면 표시
    if (callService.isConnectionFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text("영상통화")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('연결 오류: ${callService.errorMessage ?? "알 수 없는 오류"}', 
                 style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isConnecting = true;
                  });
                  _setupConnection();
                },
                child: const Text('다시 연결하기'),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("영상통화"),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
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
          // 통화 제어 버튼
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                  onPressed: _toggleMute,
                ),
                IconButton(
                  icon: Icon(_isCameraOff ? Icons.videocam_off : Icons.videocam),
                  onPressed: _toggleCamera,
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: _switchCamera,
                ),
              ],
            ),
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
