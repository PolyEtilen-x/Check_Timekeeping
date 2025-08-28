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

  factory Attendance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};

    DateTime? parseServerAt() {
      final v = d['timestamp'];
      if (v is Timestamp) return v.toDate().toLocal();
      if (v is String) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    DateTime? parseClientAt() {
      final v = d['clientAt'];
      if (v == null) return null;
      if (v is Timestamp) return v.toDate().toLocal();
      if (v is String) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    return Attendance(
      id: doc.id,
      uid: (d['uid'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      role: (d['role'] is int)
          ? d['role'] as int
          : int.tryParse('${d['role']}') ?? 1,
      status: (d['status'] ?? '') as String,
      serverAt: parseServerAt(),
      clientAt: parseClientAt(),
      by: (d['by'] ?? '') as String,
      faceImageUrl: d['faceImageUrl'] as String?,
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
