import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/responsive_page_body.dart';
import 'package:frontend/features/auth/presentation/pages/change_password.dart';
import 'package:frontend/features/auth/presentation/pages/forget_password.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';
import 'package:frontend/features/auth/presentation/pages/one_time_verification.dart';
import 'package:frontend/features/auth/presentation/pages/register.dart';

void main() {
  final phoneSizes = <Size>[
    const Size(240, 480),
    const Size(320, 568),
    const Size(430, 932),
    const Size(667, 375),
  ];

  final authPages = <Widget Function()>[
    () => const LoginScreen(),
    () => const RegisterScreen(),
    () => const ForgetPasswordScreen(),
    () => const OneTimeVerificationScreen(email: 'test@example.com'),
    () => const ChangePasswordScreen(accessToken: 'test-token'),
  ];

  for (final size in phoneSizes) {
    testWidgets('auth pages do not overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final buildPage in authPages) {
        await tester.pumpWidget(MaterialApp(home: buildPage()));
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '${buildPage().runtimeType} overflowed at $size',
        );
      }
    });
  }

  testWidgets(
    'auth pages handle large system text without horizontal overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final buildPage in authPages) {
        await tester.pumpWidget(MaterialApp(home: buildPage()));
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '${buildPage().runtimeType} overflowed with large text',
        );
      }
    },
  );

  testWidgets('page content stays readable on a wide phone viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const contentKey = Key('responsive-content');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsivePageBody(
            child: SizedBox(key: contentKey, height: 100),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(contentKey)).width, 480);
    expect(tester.takeException(), isNull);
  });
}
