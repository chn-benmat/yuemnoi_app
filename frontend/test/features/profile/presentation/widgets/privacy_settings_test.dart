import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:frontend/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/profile/presentation/pages/account/change_account_screen.dart';

class _AuthRepository extends Mock implements AuthRepository {}

void main() {
  late _AuthRepository repository;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUp(() {
    AuthSession.clear();
    repository = _AuthRepository();
    when(() => repository.close()).thenReturn(null);
  });

  tearDown(AuthSession.clear);

  Widget withAuth(Widget child) => BlocProvider(
    create: (_) => AuthBloc(authRepository: repository),
    child: child,
  );

  Future<void> openDeletionDialog(WidgetTester tester) async {
    final delete = find.text('ลบบัญชีผู้ใช้');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
  }

  testWidgets('privacy center shows password and account deletion settings', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChangeAccountScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ศูนย์ความเป็นส่วนตัว'), findsOneWidget);
    expect(find.text('บัญชีและความปลอดภัย'), findsOneWidget);
    expect(find.text('เปลี่ยนรหัสผ่าน'), findsOneWidget);
    expect(find.text('ลบบัญชีผู้ใช้'), findsOneWidget);
    expect(find.text('การยืนยันตัวตน 2 ขั้นตอน (2FA)'), findsNothing);
    expect(find.text('ความเป็นส่วนตัวและการบล็อก'), findsNothing);
    expect(find.text('จัดการผู้ใช้ที่บล็อก'), findsNothing);
    expect(find.text('ซ่อนผู้ใช้ที่ไม่ต้องการเห็น'), findsNothing);
    expect(find.text('อนุญาตให้ค้นหาโปรไฟล์ของคุณ'), findsNothing);
    expect(find.text('อุปกรณ์ที่เข้าสู่ระบบอยู่'), findsNothing);
    expect(find.text('ปิดการแจ้งเตือนทั้งหมดชั่วคราว'), findsNothing);
  });

  testWidgets('deletion confirmation shows Yuemnoi and the recovery period', (
    tester,
  ) async {
    await tester.pumpWidget(
      withAuth(const MaterialApp(home: ChangeAccountScreen())),
    );
    await openDeletionDialog(tester);

    final dialog = find.byType(AlertDialog);
    final title = find.descendant(
      of: dialog,
      matching: find.text('ลบบัญชีผู้ใช้'),
    );
    final mascot = find.descendant(
      of: dialog,
      matching: find.image(
        const AssetImage('assets/images/yuemnoi_crying.png'),
      ),
    );
    expect(mascot, findsOneWidget);
    expect(
      tester.getBottomLeft(title).dy,
      lessThan(tester.getTopLeft(mascot).dy),
    );
    expect(
      find.textContaining('โปรไฟล์และประกาศจะถูกซ่อนทันที'),
      findsOneWidget,
    );
    expect(
      find.textContaining('บัญชีจะถูกลบถาวรเมื่อครบ 30 วัน'),
      findsOneWidget,
    );
    expect(find.text('กู้คืนได้ภายใน 30 วัน'), findsOneWidget);
    expect(
      find.text('เข้าสู่ระบบอีกครั้ง แล้วกดยืนยันการกู้คืน'),
      findsOneWidget,
    );
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(
      () => repository.scheduleAccountDeletion(
        accessToken: any(named: 'accessToken'),
      ),
    );
  });

  testWidgets(
    'deletion actions stay reachable on a small screen with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 480);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        withAuth(
          MaterialApp(
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 2,
              maxScaleFactor: 2,
              child: child!,
            ),
            home: const ChangeAccountScreen(),
          ),
        ),
      );
      await openDeletionDialog(tester);

      expect(find.text('ลบบัญชี').hitTestable(), findsOneWidget);
      final cancel = find.text('ยกเลิก').hitTestable();
      expect(cancel, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('active rentals show the error and preserve the session', (
    tester,
  ) async {
    const message = 'กรุณาดำเนินรายการเช่าที่ค้างอยู่ให้เสร็จก่อนลบบัญชี';
    AuthSession.saveAccessToken('user-token');
    when(
      () => repository.scheduleAccountDeletion(accessToken: 'user-token'),
    ).thenThrow(const AuthApiException(message));
    await tester.pumpWidget(
      withAuth(const MaterialApp(home: ChangeAccountScreen())),
    );
    await openDeletionDialog(tester);
    await tester.tap(find.text('ลบบัญชี'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(AuthSession.isAuthenticated, isTrue);
  });

  testWidgets('scheduling deletion ends the session and opens login', (
    tester,
  ) async {
    AuthSession.saveAccessToken('user-token');
    when(
      () => repository.scheduleAccountDeletion(accessToken: 'user-token'),
    ).thenAnswer((_) async {});
    final router = GoRouter(
      initialLocation: AppRoutes.changeAccount,
      routes: [
        GoRoute(
          path: AppRoutes.changeAccount,
          builder: (_, _) => const ChangeAccountScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (_, _) => const Scaffold(body: Text('Login screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(withAuth(MaterialApp.router(routerConfig: router)));
    await openDeletionDialog(tester);
    await tester.tap(find.text('ลบบัญชี'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
    expect(AuthSession.isAuthenticated, isFalse);
    verify(
      () => repository.scheduleAccountDeletion(accessToken: 'user-token'),
    ).called(1);
  });
}
