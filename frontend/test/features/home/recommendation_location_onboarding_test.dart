import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/presentation/pages/recommendation_location_onboarding_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('flutter.baseflow.com/geolocator');

  for (final gpsNeverReplies in [true, false]) {
    testWidgets(
      'consent stops loading when cached location never replies (GPS pending: $gpsNeverReplies)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final pendingPosition = Completer<Map<String, dynamic>?>();
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'isLocationServiceEnabled' => true,
              'checkPermission' => LocationPermission.whileInUse.index,
              'getCurrentPosition' =>
                gpsNeverReplies
                    ? pendingPosition.future
                    : throw TimeoutException('GPS unavailable'),
              'getLastKnownPosition' => pendingPosition.future,
              _ => null,
            };
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });

        await tester.pumpWidget(
          const MaterialApp(home: RecommendationLocationOnboardingPage()),
        );
        await tester.tap(find.text('ยินยอมและใช้ตำแหน่งปัจจุบัน'));
        await tester.pump();
        expect(calls, contains('getCurrentPosition'));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 5));

        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'Consent must recover instead of leaving allow and skip disabled.',
        );
        expect(
          find.text('รับตำแหน่งไม่ได้ คุณสามารถลองใหม่หรือข้ามไปก่อน'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'ข้ามไปก่อน'))
              .onPressed,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
