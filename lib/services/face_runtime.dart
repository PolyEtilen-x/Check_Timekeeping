// lib/services/face_runtime.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'dart:ui' as ui; // <- để dùng ui.Size
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img;
import 'package:cloud_firestore/cloud_firestore.dart';

class FaceRuntime {
  FaceRuntime._();
  static final FaceRuntime instance = FaceRuntime._();

  // Cấu hình cho MobileFaceNet bạn đã tải
  static const String _modelAsset = 'assets/models/mobilefacenet.tflite';
  static const int _inputSize = 112;
  static const double _mean = 127.5;
  static const double _std  = 127.5;
  static const double _matchThreshold = 0.42;

  // Lưu embedding trong users collection
  static const String _usersCollection = 'users';
  static const String _embeddingField  = 'embedding';

  tfl.Interpreter? _interpreter;

  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
    ),
  );

  final List<_Idx> _index = [];
  bool _inited = false;
  int? _embeddingDim;

  Future<void> init() async {
    if (_inited) return;
    _interpreter ??= await tfl.Interpreter.fromAsset(_modelAsset);
    // ❗ Không đọc Firestore ở đây để tránh permission-denied khi chưa đăng nhập
    _inited = true;
  }

  Future<String?> recognizeUid(CameraImage image) async {
    if (!_inited) await init();

    // 1) Detect face(s)
    final faces = await _detectFaces(image);
    if (faces.isEmpty) return null;
    final face = _selectLargest(faces);

    // 2) YUV -> RGB -> crop -> resize
    final rgb = _yuvToRgb(image);
    final cropped = _cropSafe(rgb, face.boundingBox, expandRatio: 0.10);
    if (cropped == null) return null;
    final resized = img.copyResize(
      cropped,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.average,
    );

    // 3) run tflite + L2 normalize
    final emb = await _runEmbedding(resized);
    if (emb == null || emb.isEmpty) return null;

    // 4) Nearest by cosine
    final best = _nearestByCosine(emb, _index);
    if (best == null) return null;
    final (uid, score) = best;
    return score >= _matchThreshold ? uid : null;
  }

  Future<List<double>?> embeddingFromCameraImage(CameraImage image) async {
    if (!_inited) await init();

    // 1) detect
    final faces = await _detectFaces(image);
    if (faces.isEmpty) return null;
    final face = _selectLargest(faces);

    // 2) YUV/BGRA -> RGB -> CROP -> RESIZE
    final rgb = _yuvToRgb(image);
    final cropped = _cropSafe(rgb, face.boundingBox, expandRatio: 0.10);
    if (cropped == null) return null;
    final resized = img.copyResize(
      cropped, width: _inputSize, height: _inputSize,
      interpolation: img.Interpolation.average,
    );

    // 3) Embedding
    final emb = await _runEmbedding(resized);
    return emb;
  }

  // Trung bình nhiều embedding + L2 normalize
  List<double> meanEmbedding(List<List<double>> samples) {
    if (samples.isEmpty) return const [];
    final dim = samples.first.length;
    final acc = List<double>.filled(dim, 0.0, growable: false);

    var count = 0;
    for (final v in samples) {
      if (v.length != dim) continue;
      for (var i = 0; i < dim; i++) {
        acc[i] += v[i];
      }
      count++;
    }
    if (count == 0) return const [];
    for (var i = 0; i < dim; i++) {
      acc[i] /= count;
    }
    return _l2norm(acc);
  }

  // Lưu embedding vào Firestore và cập nhật index bộ nhớ
  Future<void> saveEmbedding(String uid, List<double> emb) async {
    if (emb.isEmpty) return;
    await FirebaseFirestore.instance
        .collection(_usersCollection)
        .doc(uid)
        .set({_embeddingField: emb}, SetOptions(merge: true));

    // Cập nhật index tại chỗ để không phải đợi refreshIndex()
    _index.removeWhere((e) => e.uid == uid);
    _index.add(_Idx(uid, emb));
  }

  Future<void> refreshIndex() async => _loadIndexFromFirestore();

  // ================= Firestore =================
  Future<void> _loadIndexFromFirestore() async {
    _index.clear();
    final qs = await FirebaseFirestore.instance
        .collection(_usersCollection)
        .get();

    for (final doc in qs.docs) {
      final data = doc.data();
      final raw = data[_embeddingField];
      if (raw is List && raw.isNotEmpty) {
        _index.add(
          _Idx(doc.id, raw.map((e) => (e as num).toDouble()).toList(growable: false)),
        );
      }
    }
    if (kDebugMode) {
      debugPrint('[FaceRuntime] loaded ${_index.length} embeddings from Firestore');
    }
    if (_index.isNotEmpty) {
      _embeddingDim = _index.first.emb.length;
    }
  }
  // ============================================

  // ======== Orientation & InputImage ==========
  int _rotation = 0;
  int _orientationToDegrees(DeviceOrientation o) {
    switch (o) {
      case DeviceOrientation.portraitUp:    return 0;
      case DeviceOrientation.landscapeLeft: return 90;
      case DeviceOrientation.portraitDown:  return 180;
      case DeviceOrientation.landscapeRight:return 270;
    }
  }

  void updateRotation(CameraDescription desc, DeviceOrientation deviceOrientation) {
    int deviceDeg = _orientationToDegrees(deviceOrientation);
    int sensor = desc.sensorOrientation; // 90, 270...
    int rotationCompensation;
    if (desc.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensor + deviceDeg) % 360;
    } else {
      rotationCompensation = (sensor - deviceDeg + 360) % 360;
    }
    _rotation = _rotationFromDegrees(rotationCompensation);
  }

  InputImage? _toMlkitInput(CameraImage cam) {
    try {
      Uint8List bytes;
      InputImageFormat format;
      int bytesPerRow;

      if (Platform.isAndroid) {
        bytes = _concatPlanes(cam.planes);
        format = InputImageFormat.yuv420;
        bytesPerRow = cam.planes.first.bytesPerRow;
      } else {
        // iOS
        bytes = cam.planes.first.bytes;
        format = InputImageFormat.bgra8888;
        bytesPerRow = cam.planes.first.bytesPerRow;
      }

      final input = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: ui.Size(cam.width.toDouble(), cam.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(_rotation) ?? InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      );
      return input;
    } catch (e) {
      if (kDebugMode) debugPrint('[FaceRuntime] _toMlkitInput error: $e');
      return null;
    }
  }
  // ============================================

  // =============== Pipeline ===================
  Future<List<Face>> _detectFaces(CameraImage cam) async {
    final input = _toMlkitInput(cam);
    if (input == null) return const [];
    final faces = await _detector.processImage(input);
    return faces;
  }

  Face _selectLargest(List<Face> faces) {
    faces.sort((a, b) {
      final aw = a.boundingBox.width;
      final ah = a.boundingBox.height;
      final bw = b.boundingBox.width;
      final bh = b.boundingBox.height;
      final aArea = aw * ah;
      final bArea = bw * bh;
      return bArea.compareTo(aArea); // giảm dần
    });
    return faces.first;
  }

  img.Image _yuvToRgb(CameraImage cam) {
    // Chuyển YUV420/BGRA8888 sang RGB bằng package:image
    if (Platform.isAndroid) {
      final w = cam.width;
      final h = cam.height;
      final yPlane = cam.planes[0];
      final uPlane = cam.planes[1];
      final vPlane = cam.planes[2];

      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      final rgb = img.Image(width: w, height: h);
      final yBytes = yPlane.bytes;

      for (int y = 0; y < h; y++) {
        final yRow = y * yPlane.bytesPerRow;
        final uvRow = (y >> 1) * uvRowStride;
        for (int x = 0; x < w; x++) {
          final uvCol = (x >> 1) * uvPixelStride;
          final yp = yBytes[yRow + x] & 0xFF;
          final up = uPlane.bytes[uvRow + uvCol] & 0xFF;
          final vp = vPlane.bytes[uvRow + uvCol] & 0xFF;

          int r = (yp + 1.370705 * (vp - 128)).round().clamp(0, 255);
          int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).round().clamp(0, 255);
          int b = (yp + 1.732446 * (up - 128)).round().clamp(0, 255);
          rgb.setPixelRgb(x, y, r, g, b);
        }
      }
      return rgb;
    } else {
      final bgra = cam.planes.first.bytes;
      final w = cam.width, h = cam.height;
      final i = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return img.copyRotate(i, angle: 0);
    }
  }

  img.Image? _cropSafe(img.Image src, Rect box, {double expandRatio = 0.0}) {
    final w = src.width.toDouble();
    final h = src.height.toDouble();
    var left = math.max(0.0, box.left - box.width * expandRatio);
    var top  = math.max(0.0, box.top  - box.height * expandRatio);
    var right  = math.min(w, box.right + box.width * expandRatio);
    var bottom = math.min(h, box.bottom + box.height * expandRatio);

    final x = left.floor();
    final y = top.floor();
    final cw = (right - left).floor();
    final ch = (bottom - top).floor();

    if (cw <= 0 || ch <= 0) return null;
    return img.copyCrop(src, x: x, y: y, width: cw, height: ch);
  }

  Future<List<double>?> _runEmbedding(img.Image input) async {
    try {
      // Chuẩn hoá [0..255] -> [-1..1]
      // final imageTensor = _preprocess(input, _inputSize, _inputSize, _mean, _std);
      final output = List<double>.filled(192, 0.0);
      var outputTensor = [output];

      // _interpreter!.run(imageTensor, outputTensor);

      final emb = outputTensor.first;
      _embeddingDim ??= emb.length;
      return _l2norm(emb);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FaceRuntime] _runEmbedding error: $e');
        debugPrint('$st');
      }
      return null;
    }
  }

  // LList<List<List<double>>> _preprocessGray(
  // img.Image im, int iw, int ih, double mean, double std) {

  // final resized = img.copyResize(im, width: iw, height: ih,
  //     interpolation: img.Interpolation.linear);

  // final input = List.generate(
  //   1,
  //   (_) => List.generate(
  //     ih, (_) => List<double>.filled(iw, 0.0, growable: false),
  //     growable: false),
  //   growable: false);

  // for (int y = 0; y < ih; y++) {
  //   for (int x = 0; x < iw; x++) {
  //     final c = resized.getPixel(x, y);     // 0xAARRGGBB
      // final r = ((c >> 16) & 0xFF).toDouble();
      // final g = ((c >>  8) & 0xFF).toDouble();
      // final b = ( c        & 0xFF).toDouble();
      // final rn = (r - mean) / std;
      // final gn = (g - mean) / std;
      // final bn = (b - mean) / std;
      // input[0][y][x] = (rn + gn + bn) / 3.0;
    // }
//   }
//   return input;
// }

  List<double> _l2norm(List<double> v) {
    double s = 0.0;
    for (final x in v) { s += x * x; }
    final n = math.sqrt(s);
    if (n == 0) return v;
    return v.map((e) => e / n).toList(growable: false);
  }

  (String, double)? _nearestByCosine(List<double> q, List<_Idx> idx) {
    if (idx.isEmpty) return null;
    String bestId = idx.first.uid;
    double best = -1.0;
    for (final it in idx) {
      final sim = _cosine(q, it.emb);
      if (sim > best) { best = sim; bestId = it.uid; }
    }
    return (bestId, best);
  }

  double _cosine(List<double> a, List<double> b) {
    if (a.length != b.length) return -1.0;
    double dot = 0.0, na = 0.0, nb = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i];
    }
    final d = math.sqrt(na) * math.sqrt(nb);
    if (d == 0) return -1.0;
    return dot / d;
  }

  int _rotationFromDegrees(int degrees) {
    switch (degrees) {
      case 0: return 0;
      case 90: return 90;
      case 180: return 180;
      case 270: return 270;
      default: return 0;
    }
  }

  Rect _scaleBox(Rect r, double sx, double sy) =>
      Rect.fromLTRB(r.left*sx, r.top*sy, r.right*sx, r.bottom*sy);

  Uint8List _concatPlanes(List<Plane> planes) {
    final bytes = planes.fold<int>(0, (p, e) => p + e.bytes.length);
    final out = Uint8List(bytes);
    int off = 0;
    for (final p in planes) {
      out.setAll(off, p.bytes);
      off += p.bytes.length;
    }
    return out;
  }
}

class _Idx {
  final String uid;
  final List<double> emb;
  _Idx(this.uid, this.emb);
}
