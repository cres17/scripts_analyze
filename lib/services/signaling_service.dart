import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String callId;

  SignalingService({required this.callId});

  Future<void> sendOffer(RTCSessionDescription offer) async {
    try {
      await _firestore.collection('calls').doc(callId).set({
        'offer': offer.toMap(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'waiting'
      });
    } catch (e) {
      debugPrint('Offer 전송 오류: $e');
      throw Exception('Offer 전송 실패');
    }
  }

  Future<void> sendAnswer(RTCSessionDescription answer) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'answer': answer.toMap(),
        'status': 'connected'
      });
    } catch (e) {
      debugPrint('Answer 전송 오류: $e');
      throw Exception('Answer 전송 실패');
    }
  }

  Future<void> sendCandidate(RTCIceCandidate candidate) async {
    try {
      await _firestore.collection('calls').doc(callId).collection('candidates').add(candidate.toMap());
    } catch (e) {
      debugPrint('ICE candidate 전송 오류: $e');
      throw Exception('ICE candidate 전송 실패');
    }
  }

  Stream<DocumentSnapshot> get callStream =>
      _firestore.collection('calls').doc(callId).snapshots();

  Stream<QuerySnapshot> get candidateStream =>
      _firestore.collection('calls').doc(callId).collection('candidates').snapshots();

  Future<void> cleanup() async {
    try {
      // 통화를 완전히 삭제하지 않고 상태만 업데이트
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ended',
        'endTimestamp': FieldValue.serverTimestamp()
      });
    } catch (e) {
      debugPrint('통화 정리 오류: $e');
    }
  }
}