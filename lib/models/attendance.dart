// lib/models/attendance.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Attendance {
  final String id;
  final String uid;
  final String name;
  final int  role;
  final String status;
  final DateTime? serverAt;
  final DateTime? clientAt;
  final String by;
  final String? faceImageUrl;

  Attendance({
    required this.id,
    required this.uid,
    required this.name,
    required this.role,
    required this.status,
    required this.serverAt,
    required this.clientAt,
    required this.by,
    this.faceImageUrl,
  });

  factory Attendance.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return Attendance(
      id: doc.id,
      uid: data['uid'] ?? '',
      name: data['name'] ?? '',
      role: (data['role'] ?? 1) is int ? (data['role'] ?? 1) : 1,
      status: data['status'] ?? 'present',
      serverAt: parseTs(data['serverAt']),
      clientAt: parseTs(data['clientAt']),
      by: data['by'] ?? 'system',
      faceImageUrl: data['faceImageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'role': role,
      'status': status,
      'clientAt': clientAt?.toIso8601String(),
      'by': by,
      if (faceImageUrl != null) 'faceImageUrl': faceImageUrl,
    };
  }
}
