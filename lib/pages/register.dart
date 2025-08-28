import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../pages/home_employee/home.dart';
import '../pages/home_manager/home.dart';
import '../services/cloudinary_service.dart';
import '../services/face_runtime.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with WidgetsBindingObserver {
  final _nameCtr = TextEditingController();
  final _emailCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  final _confirmCtr = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  int _role = 1; // 1 employee, 2 manager

  CameraController? _controller;
  bool _cameraReady = false;
  bool _streaming = false;
  bool _isSampling = false;
  int _targetSamples = 20;
  int _got = 0;
  bool _faceOK = false;
  final List<List<double>> _samples = [];
  XFile? _faceSnapshot;
  bool _busy = false;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FaceRuntime.instance.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtr.dispose();
    _emailCtr.dispose();
    _passwordCtr.dispose();
    _confirmCtr.dispose();
    _disposeCamera();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (_cameraReady) return;
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      _snack('Cần quyền Camera để đăng ký khuôn mặt.');
      return;
    }
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      FaceRuntime.instance.updateRotation(
        controller.description,
        controller.value.deviceOrientation,
      );
      controller.addListener(() {
        final ori = controller.value.deviceOrientation;
        FaceRuntime.instance.updateRotation(controller.description, ori);
      });

      setState(() {
        _controller = controller;
        _cameraReady = true;
      });
    } catch (e) {
      _snack('Không khởi tạo được camera: $e');
    }
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    await _controller?.dispose();
    _controller = null;
    _cameraReady = false;
    _streaming = false;
  }

  Future<void> _startSampling() async {
    if (!_cameraReady || _controller == null) {
      await _initCamera();
      if (!_cameraReady) return;
    }
    if (_isSampling) return;
    _samples.clear();
    _got = 0;
    _faceOK = false;
    _faceSnapshot = null;
    setState(() => _isSampling = true);

    if (!_streaming) {
      await _controller!.startImageStream(_onImage);
      setState(() => _streaming = true);
    }
  }

  Future<void> _stopSampling() async {
    if (_controller == null) return;
    try {
      await _controller!.stopImageStream();
    } catch (_) {}
    setState(() {
      _streaming = false;
      _isSampling = false;
    });
  }

  Future<void> _onImage(CameraImage img) async {
    final now = DateTime.now();
    if (now.difference(_lastAt).inMilliseconds < 250) return;
    _lastAt = now;
    if (_busy || !_isSampling) return;
    _busy = true;

    try {
      final emb = await FaceRuntime.instance.embeddingFromCameraImage(img);
      if (emb != null && emb.isNotEmpty) {
        _samples.add(emb);
        _got = _samples.length;
        if (mounted) setState(() {});
        if (_got >= _targetSamples) {
          await _stopSampling();
          try {
            _faceSnapshot = await _controller?.takePicture();
          } catch (_) {}
          final mean = FaceRuntime.instance.meanEmbedding(_samples);
          if (mean.isNotEmpty) {
            _faceOK = true;
            _snack('Đã thu mẫu khuôn mặt thành công ($_got ảnh).');
          } else {
            _faceOK = false;
            _snack('Không tạo được embedding. Vui lòng thử lại.');
          }
          if (mounted) setState(() {});
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[REGISTER] onImage error: $e');
        debugPrint('$st');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_faceOK || _samples.isEmpty) {
      _snack('Vui lòng quét đủ $_targetSamples ảnh trước khi đăng ký.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: _emailCtr.text.trim(),
              password: _passwordCtr.text);
      final uid = cred.user!.uid;
      final mean = FaceRuntime.instance.meanEmbedding(_samples);
      await FaceRuntime.instance.saveEmbedding(uid, mean);
      await FaceRuntime.instance.refreshIndex();
      String? faceUrl;
      String? facePublicId;
      if (_faceSnapshot != null) {
        try {
          final map = await CloudinaryService()
              .uploadFace(File(_faceSnapshot!.path), uid);
          faceUrl = map['url'];
          facePublicId = map['publicId'];
        } catch (_) {}
      }
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
      _snack('Có lỗi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF233986)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Image.asset('assets/logo.png', width: 180, height: 180),
                  const SizedBox(height: 20),
                  const Text('ĐĂNG KÝ',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF233986))),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameCtr,
                    decoration: _input('Họ và tên'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtr,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _input('Email'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Nhập email';
                      final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                      return ok ? null : 'Email không hợp lệ';
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtr,
                    obscureText: true,
                    decoration: _input('Mật khẩu (>= 6 ký tự)'),
                    validator: (v) =>
                        (v != null && v.length >= 6) ? null : 'Mật khẩu tối thiểu 6 ký tự',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmCtr,
                    obscureText: true,
                    decoration: _input('Xác nhận mật khẩu'),
                    validator: (v) =>
                        (v == _passwordCtr.text) ? null : 'Mật khẩu không khớp',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Vai trò:',
                          style: TextStyle(
                              color: Color(0xFF233986),
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _role,
                          items: const [
                            DropdownMenuItem(
                                value: 1, child: Text('Nhân viên (Employee)')),
                            DropdownMenuItem(
                                value: 2, child: Text('Quản lý (Manager)')),
                          ],
                          onChanged: (v) => setState(() => _role = v ?? 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_cameraReady && _controller != null)
                    Builder(builder: (context) {
                      final isPortrait =
                          MediaQuery.of(context).orientation == Orientation.portrait;
                      final camAR = _controller!.value.aspectRatio;
                      final ar = isPortrait ? (1 / camAR) : camAR;
                      return AspectRatio(
                        aspectRatio: ar,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CameraPreview(_controller!),
                        ),
                      );
                    })
                  else
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: const Text('Chưa bật camera',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.video_call),
                              onPressed: _cameraReady ? null : _initCamera,
                              label: const Text('Bật camera'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.face_retouching_natural),
                              onPressed:
                                  (!_isSampling && !_faceOK) ? _startSampling : null,
                              label: Text('Quét khuôn mặt ($_targetSamples ảnh)'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isSampling || _got > 0)
                    Column(children: [
                      LinearProgressIndicator(
                        value: (_got / _targetSamples).clamp(0.0, 1.0),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 6),
                      Text('Đã lấy: $_got / $_targetSamples',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  if (_faceOK) ...[
                    const SizedBox(height: 8),
                    const Text('✅ Khuôn mặt đã sẵn sàng',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('TẠO TÀI KHOẢN',
                              style: TextStyle(
                                  color: Color(0xFF233986),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1))),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      );
}
