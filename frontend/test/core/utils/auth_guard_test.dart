import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/utils/auth_guard.dart';
import 'package:frontend/core/widgets/login_required_dialog.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(AuthSession.clear);
  tearDown(AuthSession.clear);

  Future<List<bool>> openGuard(WidgetTester tester) async {
    final results = <bool>[];
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  results.add(
                    await AuthGuard.requireAuth(
                      context,
                      title: 'เข้าสู่ระบบเพื่อใช้งานแชท',
                      message: 'กรุณาเข้าสู่ระบบก่อนเริ่มการสนทนา',
                    ),
                  );
                },
                child: const Text('Protected action'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () {
                AuthSession.saveAccessToken('test-token');
                context.pop(true);
              },
              child: const Text('Complete login'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Complete registration'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Protected action'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('all guarded actions use the shared popup and can be dismissed', (
    tester,
  ) async {
    final results = await openGuard(tester);
    expect(find.byType(LoginRequiredDialog), findsOneWidget);
    expect(find.text('เข้าสู่ระบบเพื่อใช้งานแชท'), findsOneWidget);
    expect(find.text('ลงทะเบียน'), findsOneWidget);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(find.byType(LoginRequiredDialog), findsNothing);
  });

  testWidgets('successful login permits the guarded action', (tester) async {
    final results = await openGuard(tester);
    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequiredDialog), findsNothing);
    await tester.tap(find.text('Complete login'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets(
    'registration without a session does not permit a guarded action',
    (tester) async {
      final results = await openGuard(tester);
      await tester.tap(find.text('ลงทะเบียน'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginRequiredDialog), findsNothing);
      await tester.tap(find.text('Complete registration'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    },
  );

  testWidgets('authenticated users proceed without a login popup', (
    tester,
  ) async {
    AuthSession.saveAccessToken('test-token');
    final results = await openGuard(tester);
    expect(results, [true]);
    expect(find.byType(LoginRequiredDialog), findsNothing);
  });
}
