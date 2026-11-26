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

  testWidgets('privacy center contains privacy groups without notifications', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChangeAccountScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ศูนย์ความเป็นส่วนตัว'), findsOneWidget);
    expect(find.text('บัญชีและความปลอดภัย'), findsOneWidget);
    expect(find.text('ความเป็นส่วนตัวและการบล็อก'), findsOneWidget);
    expect(find.text('อุปกรณ์และการจัดการบัญชี'), findsOneWidget);
    expect(find.text('ปิดการแจ้งเตือนทั้งหมดชั่วคราว'), findsNothing);
  });

  testWidgets('deletion confirmation explains the 30-day recovery period', (
    tester,
  ) async {
    await tester.pumpWidget(
      withAuth(const MaterialApp(home: ChangeAccountScreen())),
    );
    await openDeletionDialog(tester);

    expect(find.textContaining('30 วัน'), findsOneWidget);
    expect(
      find.textContaining('โปรไฟล์และประกาศของคุณจะถูกซ่อน'),
      findsOneWidget,
    );
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันลบบัญชี'), findsNothing);
    verifyNever(
      () => repository.scheduleAccountDeletion(
        accessToken: any(named: 'accessToken'),
      ),
    );
  });

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
    await tester.tap(find.text('ยืนยันลบบัญชี'));
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
    await tester.tap(find.text('ยืนยันลบบัญชี'));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
    expect(AuthSession.isAuthenticated, isFalse);
    verify(
      () => repository.scheduleAccountDeletion(accessToken: 'user-token'),
    ).called(1);
  });
}
