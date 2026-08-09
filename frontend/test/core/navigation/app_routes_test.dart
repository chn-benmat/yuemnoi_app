import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';

void main() {
  testWidgets('app opens login without showing the Flutter splash', (
    tester,
  ) async {
    await tester.pumpWidget(const YuemnoiApp());

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('all application routes are registered', () {
    final settings = <RouteSettings>[
      const RouteSettings(name: AppRoutes.login),
      const RouteSettings(name: AppRoutes.home),
      const RouteSettings(name: AppRoutes.register),
      const RouteSettings(name: AppRoutes.forgotPassword),
      const RouteSettings(
        name: AppRoutes.otpVerification,
        arguments: 'test@example.com',
      ),
      const RouteSettings(
        name: AppRoutes.changePassword,
        arguments: 'test-access-token',
      ),
    ];

    for (final routeSettings in settings) {
      expect(
        AppRoutes.onGenerateRoute(routeSettings),
        isNotNull,
        reason: '${routeSettings.name} is not registered',
      );
    }
  });

  test('routes with required arguments reject missing values', () {
    expect(
      () => AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.otpVerification),
      ),
      throwsArgumentError,
    );
    expect(
      () => AppRoutes.onGenerateRoute(
        const RouteSettings(name: AppRoutes.changePassword),
      ),
      throwsArgumentError,
    );
  });
}
