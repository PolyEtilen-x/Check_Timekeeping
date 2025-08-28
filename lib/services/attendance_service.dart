// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceService {
  AttendanceService._();
  static final AttendanceService instance = AttendanceService._();

  final _col = FirebaseFirestore.instance.collection('attendance');

  String _buildDocId({required String uid, required DateTime t}) {
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$uid-$y$m$d-$hh$mm';
  }

  Future<String> recordAttendance({
    required String uid,
    required String name,
    required String role,
    required String status, // "present"
    required DateTime clientAt,
    String by = 'mobile',
    String? faceImageUrl,
  }) async {
    final docId = _buildDocId(uid: uid, t: clientAt);
    final data = <String, dynamic>{
      'uid': uid,
      'name': name,
      'role': role,
      'status': status,
      'clientAt': clientAt.toIso8601String(),
      'by': by,
      if (faceImageUrl != null) 'faceImageUrl': faceImageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    };
    await _col.doc(docId).set(data, SetOptions(merge: true));
    return docId;
  }
}
