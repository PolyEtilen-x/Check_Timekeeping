import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../pages/home_employee/home.dart';
import '../pages/home_manager/home.dart';
import '../services/cloudinary_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtr = TextEditingController();
  final _emailCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  final _confirmCtr = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _role = 1; // 1: employee, 2: manager
  bool _isLoading = false;

  XFile? _pickedFace; // ảnh đã chọn/chụp

  @override
  void dispose() {
    _nameCtr.dispose();
    _emailCtr.dispose();
    _passwordCtr.dispose();
    _confirmCtr.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
      if (x == null) return;
      setState(() => _pickedFace = x);
    } catch (e) {
      _snack('Chọn ảnh lỗi: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1024);
      if (x == null) return;
      setState(() => _pickedFace = x);
    } catch (e) {
      _snack('Chụp ảnh lỗi: $e');
    }
  }

  Future<void> _register() async {
    // ✅ đảm bảo có Form bọc các TextFormField
    final form = _formKey.currentState;
    if (form == null) {
      _snack('Form chưa được khởi tạo đúng. Hãy bấm lại.');
      return;
    }
    if (!form.validate()) return;

    // Nếu muốn bắt buộc có ảnh, giữ check này; nếu không, có thể bỏ.
    if (_pickedFace == null) {
      _snack('Vui lòng chọn/chụp 1 ảnh khuôn mặt trước khi đăng ký.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1) Tạo tài khoản Firebase Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtr.text.trim(),
        password: _passwordCtr.text,
      );
      final uid = cred.user!.uid;

      // 2) (Tuỳ chọn) Upload ảnh lên Cloudinary
      String? faceUrl;
      String? facePublicId;
      if (_pickedFace != null) {
        try {
          final map = await CloudinaryService()
              .uploadFace(File(_pickedFace!.path), uid);
          faceUrl = map['url'];
          facePublicId = map['publicId'];
        } catch (e) {
          _snack('Upload ảnh thất bại (bỏ qua): $e');
        }
      }

      // 3) Lưu thông tin user (chưa có embedding)
      final roleName = _role == 2 ? 'manager' : 'employee';
      final userData = {
        'uid': uid,
        'name': _nameCtr.text.trim(),
        'email': _emailCtr.text.trim(),
        'emailLower': _emailCtr.text.trim().toLowerCase(),
        'role': roleName,
        'roleInt': _role,
        'faceImageUrl': faceUrl,
        'facePublicId': facePublicId,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData, SetOptions(merge: true));

      if (!mounted) return;

      // 4) Điều hướng
      if (_role == 1) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeEmployee()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeManager()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Đăng ký thất bại';
      if (e.code == 'weak-password') msg = 'Mật khẩu quá yếu.';
      else if (e.code == 'email-already-in-use') msg = 'Email đã tồn tại.';
      else if (e.code == 'invalid-email') msg = 'Email không hợp lệ.';
      _snack(msg);
    } catch (e) {
      _snack('Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2B6CB0), Color(0xFF233986)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Form( // ✅ BỌC FORM Ở ĐÂY
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Đăng ký tài khoản',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _text('Họ tên', _nameCtr),
                    const SizedBox(height: 10),
                    _text('Email', _emailCtr, keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    _text('Mật khẩu', _passwordCtr, obscure: true),
                    const SizedBox(height: 10),
                    _text('Xác nhận mật khẩu', _confirmCtr, obscure: true),
                    const SizedBox(height: 10),
                    _rolePicker(),
                    const SizedBox(height: 16),

                    // Ảnh xem trước
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _pickedFace == null
                            ? const Center(
                                child: Text('Chưa có ảnh',
                                    style: TextStyle(color: Colors.white70)))
                            : Image.file(File(_pickedFace!.path), fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Chọn hoặc chụp 1 ảnh khuôn mặt rõ, đủ sáng.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),

                    // Nút chọn/chụp ảnh
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFromGallery,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Chọn ảnh'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Chụp ảnh'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF48BB78),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Đăng ký',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Đã có tài khoản? Đăng nhập',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rolePicker() {
    return DropdownButtonFormField<int>(
      value: _role,
      items: const [
        DropdownMenuItem(value: 1, child: Text('Nhân viên')),
        DropdownMenuItem(value: 2, child: Text('Quản lý')),
      ],
      onChanged: (v) => setState(() => _role = v ?? 1),
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }

  Widget _text(String label, TextEditingController ctr,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextFormField(
      controller: ctr,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: (v) {
        if ((v ?? '').trim().isEmpty) return 'Vui lòng nhập $label';
        if (label == 'Xác nhận mật khẩu' &&
            _confirmCtr.text != _passwordCtr.text) {
          return 'Mật khẩu xác nhận không khớp';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(color: Color(0xFF233986)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
