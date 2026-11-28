import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/features/profile/presentation/pages/profile/profile.dart';
import 'package:frontend/core/widgets/login_required_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

void main() {
  Future<void> openProfile(
    WidgetTester tester, {
    double textScale = 1,
    ValueNotifier<bool>? active,
  }) async {
    final bloc = _MockAuthBloc();
    when(() => bloc.state).thenReturn(const AuthInitial());
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => active == null
              ? const Scaffold(body: ProfileScreen())
              : ValueListenableBuilder<bool>(
                  valueListenable: active,
                  builder: (_, visible, _) => Scaffold(
                    body: Offstage(
                      offstage: !visible,
                      child: ProfileScreen(isActive: visible),
                    ),
                  ),
                ),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('Login page')),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (_, _) => const Scaffold(body: Text('Register page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final action in {
    'เข้าสู่ระบบ': 'Login page',
    'ลงทะเบียน': 'Register page',
  }.entries) {
    testWidgets('guest ${action.key} opens the matching auth page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openProfile(tester);

      expect(find.text('มีอุปกรณ์ไม่ได้ใช้?'), findsNothing);
      expect(find.text('ออกจากระบบ'), findsNothing);
      expect(find.byType(LoginRequiredDialog), findsOneWidget);
      final dialogBounds = tester.getRect(
        find.byKey(const ValueKey('login-required-dialog-content')),
      );
      expect(dialogBounds.width, lessThanOrEqualTo(320));
      expect(dialogBounds.height, lessThan(400));
      expect(dialogBounds.center.dx, closeTo(195, 1));
      expect(dialogBounds.center.dy, closeTo(422, 1));
      expect(find.text(action.key).hitTestable(), findsOneWidget);
      await tester.tap(find.text(action.key));
      await tester.pumpAndSettle();
      expect(find.text(action.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'compact guest profile supports larger text and guarded actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openProfile(tester, textScale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginRequiredDialog), findsNothing);
      await tester.ensureVisible(find.text('อุปกรณ์ของฉัน'));
      await tester.tap(find.text('อุปกรณ์ของฉัน'));
      await tester.pumpAndSettle();
      expect(find.text('เข้าสู่ระบบเพื่อดูอุปกรณ์'), findsOneWidget);
      expect(
        find.text('กรุณาเข้าสู่ระบบก่อนจัดการอุปกรณ์ที่คุณปล่อยเช่า'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'privacy section only displays the privacy center on mobile',
    (tester) async {
      await openProfile(tester);
      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();

      expect(find.text('ศูนย์ความเป็นส่วนตัว'), findsOneWidget);
      expect(find.text('การตั้งค่าแจ้งเตือนของเครื่อง'), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('guest prompt appears only when the profile tab becomes active', (
    tester,
  ) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await openProfile(tester, active: active);
    expect(find.byType(LoginRequiredDialog), findsNothing);

    active.value = true;
    await tester.pumpAndSettle();
    final dialog = find.byType(LoginRequiredDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('เข้าสู่ระบบก่อนใช้งาน'), findsOneWidget);
    expect(find.textContaining('เพื่อเช่าอุปกรณ์ พูดคุย'), findsNothing);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byIcon(Icons.person_outline_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequiredDialog), findsNothing);

    await tester.tap(find.text('ผู้เยี่ยมชม (Guest)'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequiredDialog), findsOneWidget);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();

    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(LoginRequiredDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
