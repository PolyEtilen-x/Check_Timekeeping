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
    await _loadIndexFromFirestore();
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
      cropped, width: _inputSize, height: _inputSize,
      interpolation: img.Interpolation.average,
    );

    // 3) Embedding
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

    // 2) YUV/BGRA -> RGB -> crop -> resize(112)
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

    // BỎ .select([...]) để tránh lỗi API; đọc thẳng và kiểm tra field.
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
  }

  // ================= Detect với ML Kit =================
  Future<List<Face>> _detectFaces(CameraImage cam) async {
    final input = _toMlkitInput(cam);
    if (input == null) return [];
    return _detector.processImage(input);
  }

  Face _selectLargest(List<Face> faces) {
    faces.sort((a, b) {
      final aa = a.boundingBox.width * a.boundingBox.height;
      final bb = b.boundingBox.width * b.boundingBox.height;
      return bb.compareTo(aa);
    });
    return faces.first;
  }

  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  InputImageRotation _rotationFromDegrees(int deg) {
    switch (deg % 360) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

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
        bytes = cam.planes.first.bytes;
        format = InputImageFormat.bgra8888;
        bytesPerRow = cam.planes.first.bytesPerRow;
      }

      final metadata = InputImageMetadata(
        size: ui.Size(cam.width.toDouble(), cam.height.toDouble()),
        rotation: _rotation, 
        format: format,
        bytesPerRow: bytesPerRow,
      );
      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }

  // Translate image & embedding =================
  img.Image _yuvToRgb(CameraImage cam) {
    final w = cam.width, h = cam.height;
    final out = img.Image(width: w, height: h);

    if (cam.format.group == ImageFormatGroup.bgra8888) {
      final p0 = cam.planes[0].bytes;
      int o = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final b = p0[o++];
          final g = p0[o++];
          final r = p0[o++];
          final a = p0[o++]; // unused
          out.setPixelRgb(x, y, r, g, b);
        }
      }
      return out;
    }

    final yPlane = cam.planes[0];
    final uPlane = cam.planes[1];
    final vPlane = cam.planes[2];

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < h; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uvRowStride;
      for (int x = 0; x < w; x++) {
        final Y = yPlane.bytes[yRow + x] & 0xFF;
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;
        final U = uPlane.bytes[uvIndex] & 0xFF;
        final V = vPlane.bytes[uvIndex] & 0xFF;

        int r = (Y + 1.370705 * (V - 128)).round();
        int g = (Y - 0.337633 * (U - 128) - 0.698001 * (V - 128)).round();
        int b = (Y + 1.732446 * (U - 128)).round();

        if (r < 0) r = 0; else if (r > 255) r = 255;
        if (g < 0) g = 0; else if (g > 255) g = 255;
        if (b < 0) b = 0; else if (b > 255) b = 255;

        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  img.Image? _cropSafe(img.Image src, Rect bbox, {double expandRatio = 0.10}) {
    double x1 = bbox.left, y1 = bbox.top, x2 = bbox.right, y2 = bbox.bottom;

    final dx = (x2 - x1) * expandRatio;
    final dy = (y2 - y1) * expandRatio;
    x1 -= dx; y1 -= dy; x2 += dx; y2 += dy;

    final ix1 = x1.floor().clamp(0, src.width - 1);
    final iy1 = y1.floor().clamp(0, src.height - 1);
    final ix2 = x2.ceil().clamp(1, src.width);
    final iy2 = y2.ceil().clamp(1, src.height);

    final cw = ix2 - ix1, ch = iy2 - iy1;
    if (cw <= 1 || ch <= 1) return null;

    return img.copyCrop(src, x: ix1, y: iy1, width: cw, height: ch);
  }

  Future<List<double>?> _runEmbedding(img.Image rgb112) async {
    if (_interpreter == null) return null;

    // image 4.x: getPixel(x,y) trả Pixel có .r/.g/.b
    final inputFloats = List<double>.filled(_inputSize * _inputSize * 3, 0.0, growable: false);
    int i = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final px = rgb112.getPixel(x, y);
        final r = px.r.toDouble();
        final g = px.g.toDouble();
        final b = px.b.toDouble();
        inputFloats[i++] = (r - _mean) / _std;
        inputFloats[i++] = (g - _mean) / _std;
        inputFloats[i++] = (b - _mean) / _std;
      }
    }

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);
    final outSize = outputTensor.shape.reduce((a, b) => a * b);

    final outputFloats = List<double>.filled(outSize, 0.0, growable: false);
    _interpreter!.run(inputFloats, outputFloats);

    _embeddingDim ??= outSize;
    return _l2norm(outputFloats);
  }

  (String, double)? _nearestByCosine(List<double> q, List<_Idx> idx) {
    if (idx.isEmpty) return null;
    String bestId = idx.first.uid;
    double best = -1.0;
    for (final it in idx) {
      final s = _cosine(q, it.emb);
      if (s > best) { best = s; bestId = it.uid; }
    }
    return (bestId, best);
  }

  List<double> _l2norm(List<double> v) {
    double s = 0.0; for (final x in v) s += x * x;
    final n = math.sqrt(s);
    final d = n == 0 ? 1.0 : n;
    return v.map((x) => x / d).toList(growable: false);
  }

  double _cosine(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < n; i++) {
      final x = a[i], y = b[i];
      dot += x * y; na += x * x; nb += y * y;
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    if (denom == 0) return 0.0;
    final v = dot / denom;
    return v.clamp(-1.0, 1.0);
  }

  Uint8List _concatPlanes(List<Plane> planes) {
    final total = planes.fold<int>(0, (s, p) => s + p.bytes.length);
    final out = Uint8List(total);
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
