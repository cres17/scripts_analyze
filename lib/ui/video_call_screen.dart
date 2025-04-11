import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../services/call_service.dart';
import 'dart:async';

class VideoCallScreen extends StatefulWidget {
  final String? callId;
  final bool isIncoming;

  const VideoCallScreen({
    Key? key, 
    this.callId, 
    this.isIncoming = false,
  }) : super(key: key);

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isInitialized = false;
  bool _isConnecting = true;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 3;
  
  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }
  
  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    setState(() {
      _isInitialized = true;
    });
    _setupCall();
  }
  
  Future<void> _setupCall() async {
    setState(() {
      _isConnecting = true;
    });
    
    try {
      final callService = Provider.of<CallService>(context, listen: false);
      
      if (widget.isIncoming && widget.callId != null) {
        debugPrint('수신 통화 시작: ${widget.callId}');
        await callService.acceptCall(widget.callId!);
      } else {
        debugPrint('발신 통화 시작');
        await callService.autoConnect();
      }
      
      debugPrint('통화 설정 완료');
      setState(() {
        _isConnecting = false;
        _isReconnecting = false;
        _reconnectAttempts = 0;
      });
    } catch (e) {
      debugPrint('통화 설정 오류: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isReconnecting = false;
        });
        
        // 오류 메시지 표시 및 재시도 옵션 제공
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('연결 실패: ${e.toString()}'),
            action: SnackBarAction(
              label: '재시도',
              onPressed: _reconnect,
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }
  
  Future<void> _reconnect() async {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('최대 재시도 횟수를 초과했습니다. 다시 시도해 주세요.'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    
    setState(() {
      _isReconnecting = true;
      _reconnectAttempts++;
    });
    
    try {
      final callService = Provider.of<CallService>(context, listen: false);
      
      // 이전 연결 해제
      await callService.endCall();
      
      // 새 연결 시도
      await Future.delayed(const Duration(seconds: 1));
      await _setupCall();
      
    } catch (e) {
      debugPrint('재연결 실패: $e');
      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재연결 실패: ${e.toString()}'),
            action: SnackBarAction(
              label: '다시 시도',
              onPressed: _reconnect,
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  // 비디오 트랙이 없는 경우를 위한 대체 UI
  Widget _buildPlaceholderVideo() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off,
              color: Colors.white,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              '비디오 없음',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            Text(
              '(에뮬레이터에서는 비디오가 비활성화됩니다)',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('화상 통화'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end),
            color: Colors.red,
            onPressed: () {
              Provider.of<CallService>(context, listen: false).endCall();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: !_isInitialized 
          ? const Center(child: CircularProgressIndicator())
          : Consumer<CallService>(
              builder: (context, callService, child) {
                // 연결 실패시 오류 화면 표시
                if (callService.isConnectionFailed) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          callService.errorMessage ?? '연결에 실패했습니다.',
                          style: const TextStyle(fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _reconnect,
                          child: Text(_isReconnecting ? '재연결 중...' : '다시 시도'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            callService.endCall();
                            Navigator.of(context).pop();
                          },
                          child: const Text('돌아가기'),
                        ),
                      ],
                    ),
                  );
                }
                
                // 연결 중이면 로딩 표시
                if (_isConnecting || _isReconnecting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _isReconnecting 
                              ? '재연결 중... (시도 ${_reconnectAttempts}/${maxReconnectAttempts})'
                              : '연결 중...',
                          style: const TextStyle(fontSize: 18),
                        ),
                        if (_isReconnecting) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              callService.endCall();
                              Navigator.of(context).pop();
                            },
                            child: const Text('취소'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                
                callService.setVideoRenderers(_localRenderer, _remoteRenderer);
                
                // 로컬 비디오 확인
                final hasLocalVideo = _localRenderer.srcObject?.getVideoTracks().isNotEmpty ?? false;
                final hasRemoteVideo = _remoteRenderer.srcObject?.getVideoTracks().isNotEmpty ?? false;
                
                // 정상 연결 시 화상 통화 화면 표시
                return Stack(
                  children: [
                    // 원격 영상 (전체 화면) 또는 대체 UI
                    Positioned.fill(
                      child: hasRemoteVideo
                          ? RTCVideoView(
                              _remoteRenderer,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : _buildPlaceholderVideo(),
                    ),
                    
                    // 로컬 영상 (작은 창) 또는 대체 UI
                    Positioned(
                      right: 16,
                      top: 16,
                      width: 120,
                      height: 160,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: hasLocalVideo
                              ? RTCVideoView(
                                  _localRenderer,
                                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  mirror: true,
                                )
                              : Container(
                                  color: Colors.grey[700],
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.mic, color: Colors.white, size: 24),
                                        SizedBox(height: 8),
                                        Text('오디오 전용', 
                                             style: TextStyle(color: Colors.white, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    
                    // 하단 컨트롤 바
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.black38,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (hasLocalVideo) IconButton(
                              icon: const Icon(Icons.switch_camera),
                              color: Colors.white,
                              onPressed: () => callService.switchCamera(),
                            ) else const SizedBox(width: 48), // 비디오가 없을 때 빈 공간
                            IconButton(
                              icon: const Icon(Icons.call_end),
                              color: Colors.red,
                              onPressed: () {
                                callService.endCall();
                                Navigator.of(context).pop();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.mic_off),
                              color: Colors.white,
                              onPressed: () => callService.toggleMute(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
  
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }
}
