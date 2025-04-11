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
  final TextEditingController _roomIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final callService = Provider.of<CallService>(context, listen: false);

    callService.localRendererStream.listen((renderer) {
      setState(() {
        _localRenderer = renderer;
      });
    });

    callService.remoteRendererStream.listen((renderer) {
      setState(() {
        _remoteRenderer = renderer;
      });
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
              if (mounted) {
                Navigator.pop(context);
              }
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
                : const Center(child: CircularProgressIndicator()),
          ),
          SizedBox(
            height: 200,
            child: _localRenderer != null
                ? RTCVideoView(
                    _localRenderer!,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _roomIdController,
                  decoration: const InputDecoration(
                    labelText: 'Room ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final roomId = _roomIdController.text.trim();
                    if (roomId.isNotEmpty) {
                      await callService.joinCall(roomId);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Room ID를 입력하세요.")),
                      );
                    }
                  },
                  icon: const Icon(Icons.video_call),
                  label: const Text('통화 참여'),
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
    _roomIdController.dispose();
    super.dispose();
  }
}
