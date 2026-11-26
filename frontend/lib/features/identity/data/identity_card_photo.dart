import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

Future<Uint8List> cropIdentityCardPhoto(
  ({Uint8List bytes, Size preview, Rect frame}) capture,
) async {
  if (capture.preview.isEmpty || capture.frame.isEmpty) {
    throw const FormatException('Invalid card image or crop');
  }

  // ตัวถอดรหัสของ Flutter จัดทิศภาพจาก EXIF ให้ตรงกับหน้ากล้อง
  final codec = await instantiateImageCodec(capture.bytes);
  final Image photo;
  try {
    photo = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }

  final ByteData? pixels;
  final int width;
  final int height;
  try {
    final source = _photoCrop(
      Size(photo.width.toDouble(), photo.height.toDouble()),
      capture.preview,
      capture.frame,
    );
    width = math.min(1800, source.width.toInt());
    height = math.max(1, (source.height * width / source.width).round());

    final recorder = PictureRecorder();
    Canvas(recorder).drawImageRect(
      photo,
      source,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final Image cropped;
    try {
      cropped = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    try {
      pixels = await cropped.toByteData();
    } finally {
      cropped.dispose();
    }
  } finally {
    photo.dispose();
  }
  if (pixels == null) throw const FormatException('Cannot read cropped photo');

  // เข้ารหัสเฉพาะพิกเซลในกรอบนอก isolate ที่วาดหน้าจอ
  return compute(_encodeCardJpeg, (
    pixels: pixels,
    width: width,
    height: height,
  ));
}

Rect _photoCrop(Size photo, Size preview, Rect frame) {
  // เทียบพิกัดกับส่วนกลางของรูปถ่ายเมื่อสัดส่วนต่างจากภาพจากกล้อง
  final scale = math.min(
    photo.width / preview.width,
    photo.height / preview.height,
  );
  final offset = Offset(
    (photo.width - preview.width * scale) / 2,
    (photo.height - preview.height * scale) / 2,
  );
  final source = Rect.fromLTRB(
    (offset.dx + frame.left * scale).ceilToDouble(),
    (offset.dy + frame.top * scale).ceilToDouble(),
    (offset.dx + frame.right * scale).floorToDouble(),
    (offset.dy + frame.bottom * scale).floorToDouble(),
  );
  if (source.isEmpty ||
      source.left < 0 ||
      source.top < 0 ||
      source.right > photo.width ||
      source.bottom > photo.height) {
    throw const FormatException('Card frame falls outside the photo');
  }
  return source;
}

Uint8List _encodeCardJpeg(({ByteData pixels, int width, int height}) crop) {
  final output = img.Image.fromBytes(
    width: crop.width,
    height: crop.height,
    bytes: crop.pixels.buffer,
    bytesOffset: crop.pixels.offsetInBytes,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(output, quality: 90);
}
