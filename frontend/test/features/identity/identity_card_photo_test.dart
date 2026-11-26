import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/data/identity_card_photo.dart';
import 'package:image/image.dart' as img;

void main() {
  for (final (photoWidth, rotate) in [
    (160, false),
    (200, false),
    (160, true),
  ]) {
    test('ตัดเฉพาะภาพในกรอบเมื่อกว้าง $photoWidth และหมุน $rotate', () async {
      final photo = img.Image(width: photoWidth, height: 320);
      img.fill(photo, color: img.ColorRgb8(220, 30, 30));
      final left = (photoWidth - 128) ~/ 2;
      img.fillRect(
        photo,
        x1: left,
        y1: 100,
        x2: left + 127,
        y2: 139,
        color: img.ColorRgb8(20, 220, 20),
      );
      img.fillRect(
        photo,
        x1: left,
        y1: 140,
        x2: left + 127,
        y2: 179,
        color: img.ColorRgb8(20, 20, 220),
      );
      final encoded = rotate
          ? img.encodeJpg(
              img.copyRotate(photo, angle: -90)..exif.imageIfd.orientation = 6,
              quality: 100,
            )
          : img.encodePng(photo);

      final result = img.decodeJpg(
        await cropIdentityCardPhoto((
          bytes: encoded,
          preview: const Size(80, 160),
          frame: const Rect.fromLTRB(8, 50, 72, 90),
        )),
      )!;

      expect((result.width, result.height), (128, 80));
      expect(result.getPixel(2, 2).g, greaterThan(180));
      expect(result.getPixel(125, 2).g, greaterThan(180));
      expect(result.getPixel(2, 77).b, greaterThan(180));
      expect(result.getPixel(125, 77).b, greaterThan(180));
      expect(result.exif.imageIfd.orientation, isNull);
    });
  }
}
