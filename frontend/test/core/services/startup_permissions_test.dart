import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const location = MethodChannel('flutter.baseflow.com/geolocator');

  setUpAll(
    () => dotenv.loadFromString(envString: 'APP_SECRET_KEY=test-app-key'),
  );
  tearDown(() {
    messenger.setMockMethodCallHandler(notifications, null);
    messenger.setMockMethodCallHandler(location, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a guest is asked for both permissions once', (tester) async {
      SharedPreferences.setMockInitialValues({});
      if (platform == TargetPlatform.android) {
        AndroidFlutterLocalNotificationsPlugin.registerWith();
      } else {
        IOSFlutterLocalNotificationsPlugin.registerWith();
      }

      final notificationDecision = Completer<bool>();
      final calls = <String>[];
      final notificationMethod = platform == TargetPlatform.android
          ? 'requestNotificationsPermission'
          : 'requestPermissions';
      messenger.setMockMethodCallHandler(notifications, (call) async {
        calls.add(call.method);
        if (call.method != notificationMethod) {
          throw StateError('Unexpected notification method: ${call.method}');
        }
        return notificationDecision.future;
      });
      messenger.setMockMethodCallHandler(location, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'checkPermission' => LocationPermission.denied.index,
          'requestPermission' => LocationPermission.whileInUse.index,
          'isLocationServiceEnabled' => true,
          'getCurrentPosition' => {
            'latitude': 13.7467785,
            'longitude': 100.534954,
            'timestamp': DateTime(2026, 1, 1).millisecondsSinceEpoch,
            'accuracy': 100.0,
          },
          _ => throw StateError('Unexpected location method: ${call.method}'),
        };
      });

      const app = YuemnoiApp(initialRoute: AppRoutes.termsOfService);
      await tester.pumpWidget(app);
      await tester.pump();
      expect(AuthSession.isAuthenticated, isFalse);
      expect(calls, [notificationMethod]);

      // การปฏิเสธแจ้งเตือนยังต้องให้ผู้ใช้ตอบคำขอตำแหน่งได้
      notificationDecision.complete(false);
      await tester.pump();
      expect(calls, [
        notificationMethod,
        'checkPermission',
        'requestPermission',
        'isLocationServiceEnabled',
        'getCurrentPosition',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      calls.clear();
      await tester.pumpWidget(app);
      await tester.pump();
      expect(calls, ['checkPermission']);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
