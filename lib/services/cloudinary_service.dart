import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const String cloudName = 'dr2m2ubf0';
  static const String unsignedPreset = 'checktimekeeping';

  final _cloudinary = CloudinaryPublic(cloudName, unsignedPreset, cache: false);

  Future<Map<String, String>> uploadFace(File file, String uid) async {
    final res = await _cloudinary.uploadFile(
      CloudinaryFile.fromFile(
        file.path,
        folder: 'faces/$uid',
        resourceType: CloudinaryResourceType.Image,
      ),
    );
    return {
      'url': res.secureUrl,
      'publicId': res.publicId,
    };
  }

  Future<File> downloadToTemp(String url, {String filename = 'face_sample.jpg'}) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('Tải ảnh mẫu thất bại: HTTP ${resp.statusCode}');
    }
    final file = File('${Directory.systemTemp.path}/$filename');
    await file.writeAsBytes(resp.bodyBytes);
    return file;
  }
}
