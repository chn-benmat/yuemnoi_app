import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';


class MediaDownloadService {
  MediaDownloadService._();
  static final MediaDownloadService instance = MediaDownloadService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// บันทึกรูปภาพ 1 รูปจาก URL ลงในแกลเลอรีของเครื่อง
  Future<bool> saveImageFromUrl(String imageUrl) async {
    if (kIsWeb) return false;
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) {
        final requestGranted = await Gal.requestAccess(toAlbum: false);
        if (!requestGranted) return false;
      }

      final response = await _dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) return false;
      final bytes = Uint8List.fromList(response.data!);
      await Gal.putImageBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('Error saving image to gallery: $e');
      return false;
    }
  }

  /// บันทึกรูปภาพหลายรูปลงในแกลเลอรีของเครื่อง
  Future<int> saveMultipleImagesFromUrls(List<String> imageUrls) async {
    if (kIsWeb || imageUrls.isEmpty) return 0;

    final hasAccess = await Gal.hasAccess(toAlbum: false);
    if (!hasAccess) {
      final requestGranted = await Gal.requestAccess(toAlbum: false);
      if (!requestGranted) return 0;
    }

    int successCount = 0;
    for (final url in imageUrls) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null) {
          final bytes = Uint8List.fromList(response.data!);
          await Gal.putImageBytes(bytes);
          successCount++;
        }
      } catch (e) {
        debugPrint('Error saving image ($url): $e');
      }
    }
    return successCount;
  }
}
