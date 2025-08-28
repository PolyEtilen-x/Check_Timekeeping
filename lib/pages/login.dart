import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/home_employee/home.dart';
import '../pages/home_manager/home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtr.dispose();
    _passwordCtr.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // Nếu đang ở phiên anonymous (bootstrap), đăng xuất trước
      final cur = FirebaseAuth.instance.currentUser;
      if (cur != null && cur.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }

      // 1) Đăng nhập Auth
      final email = _emailCtr.text.trim();
      final pass = _passwordCtr.text;

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final uid = cred.user!.uid;

      // 2) Lấy hồ sơ Firestore để biết role, name, ...
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) {
        // Hồ sơ chưa tạo đúng cách (đăng ký không hoàn tất?)
        _showSnack('Không tìm thấy hồ sơ người dùng. Vui lòng đăng ký lại.');
        await FirebaseAuth.instance.signOut();
        return;
      }
      final data = snap.data()!;
      final role = (data['role'] as int?) ?? 1;

      // (Tùy chọn) cập nhật thời gian đăng nhập gần nhất
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'lastLoginAt': FieldValue.serverTimestamp(), 'emailLower': email.toLowerCase()},
        SetOptions(merge: true),
      );

      // 3) Điều hướng theo role
      if (!mounted) return;
      if (role == 2) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeManager()),
          (_) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeEmployee()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Đăng nhập thất bại';
      switch (e.code) {
        case 'user-not-found':
          msg = 'Email chưa được đăng ký.';
          break;
        case 'wrong-password':
          msg = 'Mật khẩu không đúng.';
          break;
        case 'invalid-email':
          msg = 'Email không hợp lệ.';
          break;
        case 'user-disabled':
          msg = 'Tài khoản đã bị vô hiệu hóa.';
          break;
      }
      _showSnack(msg);
    } catch (e) {
      _showSnack('Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtr.text.trim();
    if (email.isEmpty) {
      _showSnack('Nhập email trước để nhận liên kết đặt lại mật khẩu.');
      return;
    }
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
    if (!ok) {
      _showSnack('Email không hợp lệ.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Đã gửi email đặt lại mật khẩu tới $email');
    } on FirebaseAuthException catch (e) {
      String msg = 'Không gửi được email đặt lại mật khẩu.';
      if (e.code == 'user-not-found') msg = 'Email chưa được đăng ký.';
      _showSnack(msg);
    } catch (e) {
      _showSnack('Lỗi: $e');
    }
  }

  InputDecoration _input(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(color: Color(0xFF233986)),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color(0xFF054A99)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF233986)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Logo
                  Image.asset('assets/logo.png', width: 220, height: 220),
                  const SizedBox(height: 20),

                  const Text(
                    'ĐĂNG NHẬP',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF233986),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Email
                  TextFormField(
                    controller: _emailCtr,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Color(0xFF233986), fontWeight: FontWeight.bold),
                    decoration: _input('Email'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Nhập email';
                      final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                      return ok ? null : 'Email không hợp lệ';
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordCtr,
                    obscureText: _obscure,
                    style: const TextStyle(color: Color(0xFF233986), fontWeight: FontWeight.bold),
                    decoration: _input(
                      'Mật khẩu',
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v != null && v.isNotEmpty) ? null : 'Nhập mật khẩu',
                  ),
                  const SizedBox(height: 10),

                  // Quên mật khẩu
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _forgotPassword,
                      child: const Text(
                        'Quên mật khẩu?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nút đăng nhập
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'ĐĂNG NHẬP',
                              style: TextStyle(
                                color: Color(0xFF233986),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
