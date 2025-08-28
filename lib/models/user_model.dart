import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final int role; // 1 = Employee, 2 = Manager
  final String? faceImageUrl;
  final String? facePublicId;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final List<double>? embedding;


  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.faceImageUrl,
    this.facePublicId,
    this.createdAt,
    this.lastLoginAt,
    this.embedding,
  });

  String get roleText => role == 2 ? 'Quản lý' : 'Nhân viên';

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return UserModel(
      uid: doc.id,
      name: (d['name'] ?? '') as String,
      email: (d['email'] ?? '') as String,
      role: (d['role'] ?? 1) as int,
      faceImageUrl: d['faceImageUrl'] as String?,
      facePublicId: d['facePublicId'] as String?,
      createdAt: (d['createdAt'] is Timestamp) ? (d['createdAt'] as Timestamp).toDate() : null,
      lastLoginAt: (d['lastLoginAt'] is Timestamp) ? (d['lastLoginAt'] as Timestamp).toDate() : null,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> d) {
    return UserModel(
      uid: d['uid'] as String,
      name: d['name'] as String? ?? '',
      email: d['email'] as String? ?? '',
      role: d['role'] as int? ?? 1,
      faceImageUrl: d['faceImageUrl'] as String?,
      facePublicId: d['facePublicId'] as String?,
      createdAt: d['createdAt'] as DateTime?,
      lastLoginAt: d['lastLoginAt'] as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'role': role,
        'faceImageUrl': faceImageUrl,
        'facePublicId': facePublicId,
        'createdAt': createdAt,
        'lastLoginAt': lastLoginAt,
        'embedding': embedding,
      };
}
