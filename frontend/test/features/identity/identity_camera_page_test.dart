import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/presentation/widgets/identity_camera_page.dart';

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
  Widget buildPreview(int cameraId) => const SizedBox();

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
