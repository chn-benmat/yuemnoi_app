import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:frontend/features/home/presentation/pages/home.dart';
import 'package:frontend/features/rental_item/presentation/pages/add_rental_item.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_URL=https://api.example.com');
  });

  testWidgets('app opens login without showing the Flutter splash', (
    tester,
  ) async {
    await tester.pumpWidget(const YuemnoiApp());
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('authenticated app opens home as its initial location', (
    tester,
  ) async {
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('chatbot button opens the chatbot screen', (tester) async {
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('แชตบอต'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatBotScreen), findsOneWidget);
  });

  testWidgets('home add button opens the add rental item screen', (
    tester,
  ) async {
    await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    AppRoutes.openAddRentalItem(tester.element(find.byType(HomeScreen)));
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
      ]),
    );
  });
}
