import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/presentation/widgets/stacked_images_grid_screen.dart';
import 'package:frontend/features/item_detail/presentation/widgets/full_screen_image_viewer.dart';
import 'package:mocktail/mocktail.dart';

class _IdleImageCache extends Mock implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream.empty();
}

void main() {
  const images = [
    'https://fixture.invalid/1.jpg',
    'https://fixture.invalid/2.jpg',
  ];

  setUp(() {
    CachedNetworkImageProvider.defaultCacheManager = _IdleImageCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('gal'), null);
  });

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    for (final viewer in [false, true]) {
      testWidgets(
        '${viewer ? 'viewer' : 'album'} fits width $width with large text',
        (tester) async {
          tester.view.reset();
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: viewer
                  ? const FullScreenImageViewer(imageUrls: images)
                  : const StackedImagesGridScreen(imageUrls: images),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(FilledButton), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('empty album explains state and disables saving', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StackedImagesGridScreen(imageUrls: [])),
    );
    expect(find.text('ยังไม่มีรูปภาพในอัลบั้มนี้'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'opening the second tile starts on the second photo and closes back to album',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StackedImagesGridScreen(imageUrls: images)),
      );
      await tester.tap(find.text('รูปที่ 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2/2'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(FullScreenImageViewer),
          matching: find.byTooltip('ปิด'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('รูปภาพในแชต'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final viewer in [false, true]) {
    testWidgets(
      '${viewer ? 'viewer' : 'album'} blocks duplicate saves and recovers after denied permission',
      (tester) async {
        final permission = Completer<bool>();
        var checks = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('gal'), (call) async {
              if (call.method == 'hasAccess') {
                checks++;
                return permission.future;
              }
              return false;
            });
        await tester.pumpWidget(
          MaterialApp(
            home: viewer
                ? const FullScreenImageViewer(imageUrls: images)
                : const StackedImagesGridScreen(imageUrls: images),
          ),
        );
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(find.text('กำลังบันทึก…'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(checks, 1);
        permission.complete(false);
        await tester.pump();
        await tester.pump();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        expect(find.textContaining('บันทึกไม่สำเร็จ'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('ตกลง'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
