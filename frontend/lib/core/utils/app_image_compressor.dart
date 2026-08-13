import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

class CompressedImage {
  const CompressedImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

abstract final class AppImageCompressor {
  static const _quality = 92;

  static Future<CompressedImage> compress({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final compressedBytes = await FlutterImageCompress.compressWithList(
      bytes,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (compressedBytes.isEmpty || compressedBytes.length >= bytes.length) {
      return CompressedImage(bytes: bytes, fileName: fileName);
    }

    return CompressedImage(
      bytes: compressedBytes,
      fileName: _withJpegExtension(fileName),
    );
  }

  static String _withJpegExtension(String fileName) {
    final extensionIndex = fileName.lastIndexOf('.');
    final baseName = extensionIndex > 0
        ? fileName.substring(0, extensionIndex)
        : fileName;
    return '$baseName.jpg';
  }
}
