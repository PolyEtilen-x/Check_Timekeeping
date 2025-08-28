// lib/services/face_registry_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeProfile {
  final String uid;
  final String name;
  final String role;
  final bool isActive;
  final String? avatarUrl;

  EmployeeProfile({
    required this.uid,
    required this.name,
    required this.role,
    required this.isActive,
    this.avatarUrl,
  });

  factory EmployeeProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};

    String _normalizeRole(dynamic rawRole, dynamic rawRoleInt) {
      // Ưu tiên field 'role' nếu là String
      if (rawRole is String && rawRole.isNotEmpty) return rawRole;
      // Nếu 'role' là int hoặc có 'roleInt', quy ước: 1=employee, 2=manager
      final v = (rawRole is int) ? rawRole : (rawRoleInt is int ? rawRoleInt : 1);
      return v == 2 ? 'manager' : 'employee';
    }

    final role = _normalizeRole(d['role'], d['roleInt']);
    return EmployeeProfile(
      uid: doc.id,
      name: (d['name'] ?? '') as String,
      role: role,
      isActive: (d['isActive'] ?? true) as bool,
      avatarUrl: d['avatarUrl'] as String?,
    );
  }
}

class FaceRegistryService {
  FaceRegistryService._();
  static final FaceRegistryService instance = FaceRegistryService._();

  String collectionPath = 'users'; 
  final Map<String, EmployeeProfile> _cache = {};

  Future<EmployeeProfile?> getByUid(String uid, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(uid)) return _cache[uid];
    final col = FirebaseFirestore.instance.collection(collectionPath).withConverter(
      fromFirestore: (snap, _) => EmployeeProfile.fromDoc(snap),
      toFirestore: (EmployeeProfile p, _) => <String, dynamic>{
        'name': p.name,
        'role': p.role,
        'isActive': p.isActive,
        if (p.avatarUrl != null) 'avatarUrl': p.avatarUrl,
      },
    );
    final doc = await col.doc(uid).get();
    if (!doc.exists) return null;
    final profile = doc.data();
    if (profile != null) _cache[uid] = profile;
    return profile;
  }
}
