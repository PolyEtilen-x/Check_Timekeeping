import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../timekeeping/timekeeping.dart'; 
import '../employee/employee_list_page.dart';
import '../timekeeping/timekeeping_list_page.dart'; 

class HomeManager extends StatefulWidget {
  const HomeManager({super.key});

  @override
  State<HomeManager> createState() => _HomeManagerState();
}

class _HomeManagerState extends State<HomeManager> {
  String? _name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      _name = snap.data()?['name'] ?? '';
      _loading = false;
    });
  }

  Widget _buildButton({
    required String text,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF054A99),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: Row(
          children: [
            if (icon != null) Icon(icon, color: const Color(0xFF233986)),
            if (icon != null) const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF233986)),
          ],
        ),
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
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              Center(
                child: Image.asset('assets/logo.png', width: 150, height: 150),
              ),
              const SizedBox(height: 50),

              Text(
                _loading ? 'Xin chào...' : 'Xin chào, ${_name ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF233986),
                ),
              ),

              const SizedBox(height: 30),

              // Các nút
              _buildButton(
                text: 'CHẤM CÔNG',
                icon: Icons.face_retouching_natural,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimeKeepingPage()),
                  );
                },
              ),
              _buildButton(
                text: 'DANH SÁCH NHÂN VIÊN',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EmployeeListPage()),
                  );
                },
              ),
              _buildButton(
                text: 'DANH SÁCH CHẤM CÔNG',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimeKeepingListPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
