// lib/pages/timekeeping/timekeeping_page.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/attendance_service.dart';
import '../../services/face_runtime.dart';
import '../../services/face_registry_service.dart';

class TimeKeepingPage extends StatefulWidget {
  const TimeKeepingPage({super.key});

  @override
  State<TimeKeepingPage> createState() => _TimeKeepingPageState();
}

class _TimeKeepingPageState extends State<TimeKeepingPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  

  // UI state
  String _status = 'idle';
  String? _name;
  String? _role;
  DateTime? _timeIn;

  // Debug / metrics
  bool _streaming = false;
  int _frames = 0;
  DateTime? _lastFrameAt;

  // Pipeline control
  bool _isProcessing = false;

  // Watchdog
  Timer? _wd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _startWatchdog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopWatchdog();
    _stopStream();
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      await _stopStream();
      await _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      // Làm mới index phòng khi users mới được “enroll”
      try {
        await FaceRuntime.instance.refreshIndex();
      } catch (_) {}
      await _initCamera();
      await _startStream();
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _status = 'request-permission');

    final granted = await Permission.camera.request().isGranted;
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cần quyền camera để chấm công')),
        );
        setState(() => _status = 'permission-denied');
      }
      return;
    }

    // ✅ KHỞI TẠO FACERUNTIME: nạp model TFLite + embeddings từ Firestore
    setState(() => _status = 'loading-face-runtime');
    try {
      await FaceRuntime.instance.init();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TK] FaceRuntime init error: $e');
        debugPrint('$st');
      }
      setState(() => _status = 'face-runtime-error');
      return;
    }

    await _initCamera();
    await _startStream();
  }

  Future<void> _initCamera() async {
    setState(() => _status = 'initializing');
    final cams = await availableCameras();
    if (cams.isEmpty) {
      setState(() => _status = 'no-camera');
      return;
    }
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );

    final ctrl = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _controller = ctrl;
    _initFuture = ctrl.initialize();

    FaceRuntime.instance.updateRotation(
      ctrl.description,
      ctrl.value.deviceOrientation,
    );
    // reset rotation khi xoay thiết bị
    ctrl.addListener(() {
      final ori = _controller?.value.deviceOrientation;
      if (ori != null) {
        FaceRuntime.instance.updateRotation(_controller!.description, ori);
      }
    });

    try {
      await _initFuture;
      if (!mounted) return;
      setState(() => _status = 'initialized');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TK] init camera error: $e');
        debugPrint('$st');
      }
      setState(() => _status = 'init-error');
    }
  }


  Future<void> _disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _initFuture = null;
    if (mounted) setState(() {});
  }

  Future<void> _startStream() async {
    if (_controller == null) return;

    // Chờ init xong
    if (_initFuture != null) {
      try {
        await _initFuture;
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    if (!_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) {
      _streaming = true;
      if (mounted) setState(() => _status = 'streaming');
      return;
    }

    try {
      setState(() => _status = 'starting-stream');
      await _controller!.startImageStream((CameraImage image) async {
        _streaming = true;
        _frames += 1;
        _lastFrameAt = DateTime.now();

        if (_isProcessing) return;
        _isProcessing = true;
        if (mounted) setState(() => _status = 'detecting');

        try {
          // 1) NHẬN DIỆN → UID (on-device, MobileFaceNet)
          final uid = await FaceRuntime.instance.recognizeUid(image);
          if (uid == null) {
            if (mounted) setState(() => _status = 'streaming · no match');
            return;
          }

          // 2) LẤY HỒ SƠ TỪ FIRESTORE THEO UID
          final profile = await FaceRegistryService.instance.getByUid(uid);
          if (profile == null) {
            if (mounted) setState(() => _status = 'profile-not-found');
            return;
          }
          if (!profile.isActive) {
            if (mounted) setState(() => _status = 'inactive-user');
            return;
          }

          // 3) GHI CHẤM CÔNG
          _name = profile.name;
          _role = profile.role;
          _timeIn = DateTime.now();
          if (mounted) setState(() => _status = 'saving');

          final docId = await AttendanceService.instance.recordAttendance(
            uid: profile.uid,
            name: profile.name,
            role: profile.role,
            status: 'present',
            clientAt: _timeIn!,
          );
          if (kDebugMode) debugPrint('[TK] attendance saved: $docId');
          if (mounted) setState(() => _status = 'saved');
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('[TK] pipeline error: $e');
            debugPrint('$st');
          }
          if (mounted) setState(() => _status = 'pipeline-error');
        } finally {
          _isProcessing = false;
        }
      });

      if (kDebugMode) debugPrint('[TK] startImageStream OK');
      if (mounted) setState(() => _status = 'streaming');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TK] startImageStream error: $e');
        debugPrint('$st');
      }
      if (mounted) {
        setState(() {
          _streaming = false;
          _status = 'stream-error';
        });
      }
    }
  }

  Future<void> _stopStream() async {
    try {
      if (_controller?.value.isStreamingImages == true) {
        await _controller?.stopImageStream();
      }
    } catch (_) {}
    _streaming = false;
    if (mounted) setState(() {});
  }

  void _startWatchdog() {
    _wd?.cancel();
    _wd = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted) return;
      if (_controller == null) return;
      if (!_streaming) return;

      final last = _lastFrameAt;
      if (last == null) return;

      final diff = DateTime.now().difference(last).inMilliseconds;
      if (diff > 3000) {
        if (kDebugMode) debugPrint('[TK] watchdog: restart stream');
        await _stopStream();
        await _startStream();
      }
    });
  }

  void _stopWatchdog() {
    _wd?.cancel();
    _wd = null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _controller?.value.isInitialized == true
        ? CameraPreview(_controller!)
        : const Center(
            child: Text('Đang khởi tạo camera...',
                style: TextStyle(color: Colors.white70)));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Chấm công bằng khuôn mặt (Firebase)'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: preview),
          Positioned(
            left: 12,
            top: 12,
            child: _StatusChip(
              status: _status,
              frames: _frames,
              streaming: _streaming,
              lastFrameAt: _lastFrameAt,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: _BottomPanel(
              name: _name,
              role: _role,
              timeIn: _timeIn,
              onStart: () async {
                await _startStream();
              },
              onStop: () async {
                await _stopStream();
              },
              onRestart: () async {
                await _stopStream();
                await _startStream();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final int frames;
  final bool streaming;
  final DateTime? lastFrameAt;

  const _StatusChip({
    required this.status,
    required this.frames,
    required this.streaming,
    required this.lastFrameAt,
  });

  @override
  Widget build(BuildContext context) {
    final extra = [
      'frames:$frames',
      if (streaming) 'on',
      if (lastFrameAt != null)
        'last:${lastFrameAt!.toIso8601String().split("T").last.split(".").first}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(
            extra.isEmpty ? status : '$status · $extra',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final String? name;
  final String? role;
  final DateTime? timeIn;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  const _BottomPanel({
    required this.name,
    required this.role,
    required this.timeIn,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final hasRec = name != null && role != null && timeIn != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRec)
            Text(
              '$name ($role) · ${timeIn!.toLocal().toIso8601String().replaceFirst("T", " ").split(".").first}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            )
          else
            const Text(
              'Chưa nhận diện',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Bắt đầu'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Dừng'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Khởi động lại'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
