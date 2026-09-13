import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/app_orientation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppOrientationService Tests', () {
    test('identifies phone sizes as not tablet (shortestSide < 600)', () {
      expect(
        AppOrientationService.isTabletFromSize(const Size(390, 844)),
        isFalse,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(412, 915)),
        isFalse,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(360, 640)),
        isFalse,
      );
    });

    test('identifies tablet/iPad sizes correctly (shortestSide >= 600)', () {
      expect(
        AppOrientationService.isTabletFromSize(const Size(600, 960)),
        isTrue,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(768, 1024)),
        isTrue,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(834, 1194)),
        isTrue,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(1024, 1366)),
        isTrue,
      );
      expect(
        AppOrientationService.isTabletFromSize(const Size(1280, 800)),
        isTrue,
      );
    });

    test('applyOrientation executes without throwing error', () async {
      await expectLater(
        AppOrientationService.applyOrientation(isTablet: false),
        completes,
      );
      await expectLater(
        AppOrientationService.applyOrientation(isTablet: true),
        completes,
      );
    });

    test('setupOrientation executes without throwing error', () async {
      await expectLater(AppOrientationService.setupOrientation(), completes);
    });
  });
}
