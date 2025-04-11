import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String callId;

  SignalingService({required this.callId});

  Future<void> sendOffer(RTCSessionDescription offer) async {
    await _firestore.collection('calls').doc(callId).set({'offer': offer.toMap()});
  }

  Future<void> sendAnswer(RTCSessionDescription answer) async {
    await _firestore.collection('calls').doc(callId).update({'answer': answer.toMap()});
  }

  Future<void> sendCandidate(RTCIceCandidate candidate) async {
    await _firestore.collection('calls').doc(callId).collection('candidates').add(candidate.toMap());
  }

  Stream<DocumentSnapshot> get callStream =>
      _firestore.collection('calls').doc(callId).snapshots();

  Stream<QuerySnapshot> get candidateStream =>
      _firestore.collection('calls').doc(callId).collection('candidates').snapshots();

  Future<void> cleanup() async {
    await _firestore.collection('calls').doc(callId).delete();
  }
}