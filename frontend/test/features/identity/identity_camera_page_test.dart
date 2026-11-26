import 'dart:async';

import 'package:camera/camera.dart' show CameraPreview;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/presentation/widgets/identity_camera_page.dart';
import 'package:image/image.dart' as img;

const _surfaceError =
    'releaseFlutterSurfaceTexture() cannot be called if the '
    'flutterSurfaceProducer for the camera preview has not yet been initialized.';

class _CameraPlatform extends CameraPlatform {
  bool failInitialization = true;
  bool failDisposal = true;
  Object initializationError = PlatformException(
    code: 'CameraInitializationFailed',
  );
  int creations = 0;
  Completer<void>? camerasGate;
  Completer<void>? initializationGate;
  Completer<void>? disposalGate;
  XFile? picture;
  final disposed = <int>[];
  final orientationLocks = <int>[];
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async {
    await camerasGate?.future;
    return const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => ++creations;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((event) => event.cameraId == cameraId);

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializationGate?.future;
    if (failInitialization) {
      throw initializationError;
    }
    initialized.add(
      CameraInitializedEvent(
        cameraId,
        1280,
        720,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {
    orientationLocks.add(cameraId);
  }

  @override
  Widget buildPreview(int cameraId) =>
      const ColoredBox(color: Color(0xFF24CC48));

  @override
  Future<XFile> takePicture(int cameraId) async => picture!;

  @override
  Future<void> dispose(int cameraId) async {
    disposed.add(cameraId);
    await disposalGate?.future;
    if (failDisposal) {
      throw PlatformException(
        code: 'IllegalStateException',
        message: _surfaceError,
      );
    }
  }
}

void main() {
  late CameraPlatform original;
  late _CameraPlatform platform;

  setUp(() {
    original = CameraPlatform.instance;
    platform = _CameraPlatform();
    CameraPlatform.instance = platform;
  });

  tearDown(() {
    CameraPlatform.instance = original;
  });

  testWidgets('แสดงวงตราซ้ายบนและกรอบรูปถ่ายขวาล่างในกรอบบัตร', (tester) async {
    platform.failInitialization = false;
    platform.failDisposal = false;
    final screen = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: const MaterialApp(
          home: IdentityCameraPage(kind: IdentityCaptureKind.card),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final frame = tester.getRect(
      find.byKey(const ValueKey('identity_card_capture_frame')),
    );
    await tester.runAsync(() async {
      final boundary =
          screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await boundary.toImage();
      try {
        final data = (await screenshot.toByteData())!;
        int sample(Offset point) => data.getUint32(
          (point.dy.floor() * screenshot.width + point.dx.floor()) * 4,
        );

        int sampleOnCard(double x, double y) => sample(
          Offset(frame.left + frame.width * x, frame.top + frame.height * y),
        );
        const cameraColor = 0x24CC48FF;
        expect(sampleOnCard(0.085, 0.13), cameraColor);
        expect(sampleOnCard(0.86, 0.73), cameraColor);
        expect(sampleOnCard(0.085, 0.038), isNot(cameraColor));
        expect(sampleOnCard(0.86, 0.50), isNot(cameraColor));
      } finally {
        screenshot.dispose();
      }
    });

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('กรอบบัตรอยู่ในภาพกล้องและหน้าตรวจรูปแสดงเฉพาะภาพในกรอบ', (
    tester,
  ) async {
    platform.failInitialization = false;
    platform.failDisposal = false;
    final cameraImage = img.Image(width: 90, height: 160);
    img.fill(cameraImage, color: img.ColorRgb8(220, 20, 20));
    img.fillRect(
      cameraImage,
      x1: 3,
      y1: 54,
      x2: 86,
      y2: 105,
      color: img.ColorRgb8(20, 220, 20),
    );
    platform.picture = XFile.fromData(img.encodePng(cameraImage));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(380, 790);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pumpAndSettle();

    final preview = find.byType(CameraPreview);
    final frame = find.descendant(
      of: preview,
      matching: find.byKey(const ValueKey('identity_card_capture_frame')),
    );
    expect(frame, findsOneWidget);
    final previewRect = tester.getRect(preview);
    final frameRect = tester.getRect(frame);
    expect((frameRect.center - previewRect.center).distance, lessThan(0.01));
    expect(frameRect.width, lessThan(previewRect.width));
    expect(frameRect.height, lessThan(previewRect.height));
    expect(frameRect.width / frameRect.height, closeTo(85.6 / 53.98, 0.01));

    // รูปที่ตัดแล้วต้องแสดงได้แม้ CameraX ยังคืนกล้องไม่เสร็จ
    final release = platform.disposalGate = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('ถ่ายภาพ'));
      final timer = Stopwatch()..start();
      while (find.text('ใช้รูปนี้').evaluate().isEmpty &&
          timer.elapsed < const Duration(seconds: 2)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(find.text('ใช้รูปนี้'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    final result = img.decodeJpg(image.bytes)!;
    expect((result.width, result.height), (84, 52));
    expect(result.getPixel(0, 0).g, greaterThan(180));
    expect(result.getPixel(83, 51).g, greaterThan(180));

    release.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'เปิดกล้องล้มเหลวและคืน surface ไม่ได้ต้องหยุดโหลดและลองใหม่ได้',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IdentityCameraPage(kind: IdentityCaptureKind.card),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('ลองเปิดกล้องอีกครั้ง'), findsOneWidget);
      expect(platform.disposed, [1]);

      platform.failInitialization = false;
      platform.failDisposal = false;
      await tester.tap(find.text('ลองเปิดกล้องอีกครั้ง'));
      await tester.pumpAndSettle();

      expect(platform.creations, 2);
      expect(find.byTooltip('ถ่ายภาพ'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('กลับเข้าแอประหว่างเริ่มกล้องต้องรอคืนกล้องเก่าก่อนเปิดตัวใหม่', (
    tester,
  ) async {
    platform.failInitialization = false;
    platform.failDisposal = false;
    final gate = platform.initializationGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pump();
    expect(platform.creations, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.creations, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(platform.disposed, [1]);
    expect(platform.creations, 2);
    expect(find.byTooltip('ถ่ายภาพ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('กลับเข้าแอประหว่างคืนกล้องต้องรอ surface เก่าก่อน', (
    tester,
  ) async {
    platform.failInitialization = false;
    platform.failDisposal = false;
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pumpAndSettle();
    final gate = platform.disposalGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.disposed, [1]);
    expect(platform.creations, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(platform.creations, 2);
    expect(find.byTooltip('ถ่ายภาพ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final error in [
    PlatformException(code: 'CameraAccessDenied'),
    StateError('Camera initialization failed'),
  ]) {
    testWidgets('คืนกล้องล้มเหลวต้องยังแสดงข้อผิดพลาด ${error.runtimeType}', (
      tester,
    ) async {
      platform.initializationError = error;
      await tester.pumpWidget(
        const MaterialApp(
          home: IdentityCameraPage(kind: IdentityCaptureKind.card),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('ลองเปิดกล้องอีกครั้ง'), findsOneWidget);
      if (error is PlatformException) {
        expect(find.text('เปิดการตั้งค่ากล้อง'), findsOneWidget);
      } else {
        expect(find.text('กล้องยังไม่พร้อม กรุณาลองใหม่'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('ออกจากหน้าระหว่างค้นหากล้องต้องไม่สร้างกล้องตามมาภายหลัง', (
    tester,
  ) async {
    final gate = platform.camerasGate = Completer<void>();
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(platform.creations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ออกจากหน้าระหว่างเริ่มกล้องต้องคืนกล้องโดยไม่ล็อกทิศภาพต่อ', (
    tester,
  ) async {
    platform.failInitialization = false;
    platform.failDisposal = false;
    final gate = platform.initializationGate = Completer<void>();
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pump();
    expect(platform.creations, 1);
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(platform.disposed, [1]);
    expect(platform.orientationLocks, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
