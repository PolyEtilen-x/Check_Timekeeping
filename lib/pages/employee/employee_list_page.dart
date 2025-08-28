import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  final _searchCtr = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtr.dispose();
    super.dispose();
  }

  // Stream đọc nhân viên (role = 1)
  Stream<List<UserModel>> _employeeStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 1)
        .orderBy('name')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .snapshots()
        .map((qs) => qs.docs
            .map((d) => UserModel.fromFirestore(
                  d as DocumentSnapshot<Map<String, dynamic>>,
                ))
            .toList());
  }

  // Mock để test UI khi chưa có Firestore
  List<UserModel> mockEmployees() => [
        UserModel(
          uid: 'u1',
          name: 'Nguyễn An',
          email: 'an@example.com',
          role: 1,
          faceImageUrl:
              'https://picsum.photos/seed/an/200/200', // ảnh demo
        ),
        UserModel(
          uid: 'u2',
          name: 'Trần Bình',
          email: 'binh@example.com',
          role: 1,
          faceImageUrl: 'https://picsum.photos/seed/binh/200/200',
        ),
        UserModel(
          uid: 'u3',
          name: 'Lê Cẩm',
          email: 'cam@example.com',
          role: 1,
          faceImageUrl: 'https://picsum.photos/seed/cam/200/200',
        ),
      ];

  Widget _item(UserModel u) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: u.faceImageUrl != null && u.faceImageUrl!.isNotEmpty
              ? Image.network(u.faceImageUrl!, width: 46, height: 46, fit: BoxFit.cover)
              : Container(
                  width: 46,
                  height: 46,
                  color: const Color(0xFFEAEAEA),
                  child: const Icon(Icons.person, color: Color(0xFF233986)),
                ),
        ),
        title: Text(
          u.name,
          style: const TextStyle(
            color: Color(0xFF233986),
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          u.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black54),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF233986).withOpacity(.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            u.roleText.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF233986),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () {
          // TODO: điều hướng sang trang chi tiết nhân viên nếu cần
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgGradient = LinearGradient(
      colors: [Colors.white, Color(0xFF054A99)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF233986)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'DANH SÁCH NHÂN VIÊN',
                      style: TextStyle(
                        color: Color(0xFF233986),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search box (nền trắng, bo tròn)
                TextField(
                  controller: _searchCtr,
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  style: const TextStyle(color: Color(0xFF233986), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên hoặc email...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF233986)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // List
                Expanded(
                  child: StreamBuilder<List<UserModel>>(
                    stream: _employeeStream(),
                    builder: (context, snap) {
                      // Nếu bạn muốn test UI không cần Firestore, dùng mock:
                      // final data = mockEmployees().where(...).toList();
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Lỗi tải danh sách: ${snap.error}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final items = (snap.data ?? []);
                      // filter client-side theo _q
                      final filtered = items.where((u) {
                        if (_q.isEmpty) return true;
                        final name = u.name.toLowerCase();
                        final email = u.email.toLowerCase();
                        return name.contains(_q) || email.contains(_q);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'Không có nhân viên phù hợp.',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _item(filtered[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
