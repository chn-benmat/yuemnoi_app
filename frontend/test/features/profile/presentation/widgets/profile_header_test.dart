import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/profile_widgets.dart';

void main() {
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('profile header fits width $width and opens profile', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Column(
                children: [
                  ProfileHeader(
                    displayName: 'ชื่อผู้ใช้ที่ยาวมากสำหรับทดสอบหน้าจอขนาดเล็ก',
                    avatarUrl: null,
                    onProfileTap: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('ดูโปรไฟล์'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
