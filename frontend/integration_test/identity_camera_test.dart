import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/presentation/widgets/identity_camera_page.dart';
import 'package:integration_test/integration_test.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  await tester.pump();
  for (var attempt = 0; attempt < 150 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    finder,
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join('\n'),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  // ต้องอนุญาตสิทธิ์กล้องบนอุปกรณ์ทดสอบก่อนรัน เพื่อไม่รอหน้าต่าง Android
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('เปิดกล้อง ถ่าย และถ่ายใหม่ได้ทั้งบัตรและใบหน้า', (tester) async {
    for (final kind in IdentityCaptureKind.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: IdentityCameraPage(key: ValueKey(kind), kind: kind),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _waitFor(tester, find.byType(CameraPreview));
      await tester.tap(find.byTooltip('ถ่ายภาพ'));
      await _waitFor(tester, find.text('ใช้รูปนี้'));
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('ถ่ายใหม่'));
      await _waitFor(tester, find.byType(CameraPreview));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      for (var cycle = 0; cycle < 3; cycle++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _waitFor(tester, find.byType(CameraPreview));
        expect(
          tester
              .widget<CameraPreview>(find.byType(CameraPreview))
              .controller
              .value
              .isInitialized,
          isTrue,
        );
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
  });
}
