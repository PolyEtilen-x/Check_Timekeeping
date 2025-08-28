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
  bool _streaming = false;
  bool _isProcessing = false;
  int _frames = 0;
  String _status = 'idle';
  String? _matchName;
  int? _role; // 1 employee, 2 manager
  DateTime? _timeIn;
  DateTime? _lastFrameAt;

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
      // Refresh index to pick up any new enrollments
      try {
        await FaceRuntime.instance.refreshIndex();
      } catch (_) {}
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
    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    setState(() {
      _controller = controller;
      _status = 'camera-ready';
    });
  }

  Future<void> _disposeCamera() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  Future<void> _startStream() async {
    if (_controller == null) {
      await _initCamera();
      if (_controller == null) return;
    }
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

          // 3) GHI CÔNG
          _matchName = profile.name;
          _role = profile.role as int?;
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

          try { await _stopStream(); } catch (_) {}

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
      if (mounted) setState(() => _status = 'stream-error');
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
          child: Column(
            children: [
              const SizedBox(height: 6),
              _header(),
              const SizedBox(height: 8),
              Expanded(child: _cameraView()),
              _panel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Chấm công',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _status,
              style: const TextStyle(color: Colors.white),
            ),
          )
        ],
      ),
    );
  }

  Widget _cameraView() {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _controller != null
            ? CameraPreview(_controller!)
            : const Center(
                child: Text('Camera chưa sẵn sàng',
                    style: TextStyle(color: Colors.white70))),
      ),
    );
  }

  Widget _panel() {
    return _Panel(
      status: _status,
      frames: _frames,
      streaming: _streaming,
      lastFrameAt: _lastFrameAt,
      matchName: _matchName,
      role: _role,
      onStart: _startStream,
      onStop: _stopStream,
      onRestart: () async {
        await _stopStream();
        await _disposeCamera();
        await _initCamera();
        await _startStream();
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final String status;
  final int frames;
  final bool streaming;
  final DateTime? lastFrameAt;
  final String? matchName;
  final int? role;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final Future<void> Function() onRestart;

  const _Panel({
    required this.status,
    required this.frames,
    required this.streaming,
    required this.lastFrameAt,
    required this.matchName,
    required this.role,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
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
      margin: const EdgeInsets.only(top: 8, left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Trạng thái: $status · $extra',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (matchName != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$matchName${role == null ? '' : role == 2 ? ' (QL)' : ' (NV)'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: const Icon(Icons.play_arrow),
              ),
              OutlinedButton(
                onPressed: onStop,
                style: OutlinedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: const Icon(Icons.stop),
              ),
              ElevatedButton(
                onPressed: onRestart,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                  backgroundColor: Colors.blueGrey,
                ),
                child: const Icon(Icons.restart_alt),
              ),
            ],
          )
        ],
      ),
    );
  }
}
