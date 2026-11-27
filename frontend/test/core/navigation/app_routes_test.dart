import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:frontend/features/home/presentation/pages/home.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/profile/presentation/pages/account/promptpay_account_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/setting_account_screen.dart';
import 'package:frontend/features/rental_item/presentation/pages/add_rental_item.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockIdentityRepository extends Mock implements IdentityRepository {}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_URL=https://api.example.com');
  });

  testWidgets('a guest opens the home feed from the default route', (
    tester,
  ) async {
    AuthSession.clear();
    await tester.pumpWidget(const YuemnoiApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('authenticated app opens home as its initial location', (
    tester,
  ) async {
    AuthSession.saveAccessToken('user-token');
    addTearDown(AuthSession.clear);
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('PromptPay settings deep link requires an app session', (
    tester,
  ) async {
    AuthSession.clear();
    await tester.pumpWidget(
      const YuemnoiApp(initialRoute: AppRoutes.promptPayAccount),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('account settings opens PromptPay and returns to the menu', (
    tester,
  ) async {
    AuthSession.saveAccessToken('user-token');
    addTearDown(AuthSession.clear);
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.settingAccount,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('แก้ไขพร้อมเพย์'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PromptPayAccountScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(SettingAccountScreen), findsOneWidget);
  });

  testWidgets('chatbot button opens the chatbot screen', (tester) async {
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('แชตบอต'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatBotScreen), findsOneWidget);
  });

  testWidgets('adding an item requires the approved card and saved phone', (
    tester,
  ) async {
    AuthSession.saveAccessToken('user-token');
    addTearDown(AuthSession.clear);
    final repository = _MockIdentityRepository();
    var phoneSaved = false;
    when(repository.status).thenAnswer(
      (_) async => IdentityStatus({
        'rental_verification': {
          'id_card_approved': true,
          'contact_phone_saved': phoneSaved,
          'identity_pending': false,
        },
      }),
    );
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final context = tester.element(find.byType(HomeScreen));
    AppRoutes.openAddRentalItem(context, identityRepository: repository);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ยืนยันข้อมูลก่อนเพิ่มสินค้า'), findsOneWidget);
    expect(find.text('เพิ่มเบอร์โทรศัพท์'), findsOneWidget);
    expect(find.text('ยืนยันบัตรประชาชน'), findsNothing);
    expect(find.byType(AddRentalItemScreen), findsNothing);
    await tester.tap(find.text('ปิด'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    phoneSaved = true;
    AppRoutes.openAddRentalItem(context, identityRepository: repository);
    await tester.pumpAndSettle();

    expect(find.byType(AddRentalItemScreen), findsOneWidget);
  });

  test('all application routes are registered', () {
    final router = AppRoutes.createRouter();
    addTearDown(router.dispose);

    final paths = router.configuration.routes.whereType<GoRoute>().map(
      (route) => route.path,
    );

    expect(
      paths,
      containsAll([
        AppRoutes.login,
        AppRoutes.home,
        AppRoutes.chatbot,
        AppRoutes.chatDetail,
        AppRoutes.register,
        AppRoutes.forgotPassword,

        AppRoutes.otpVerification,
        AppRoutes.changePassword,
        AppRoutes.addRentalItem,
        AppRoutes.itemAutoReply,
        AppRoutes.promptPayAccount,
      ]),
    );
  });
}
