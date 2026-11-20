import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_payment_success_screen.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renter returns to chat after success from an imperative route', (
    tester,
  ) async {
    Object? receivedExtra;
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const RentalPaymentSuccessScreen(returnToChat: true),
                ),
              ),
              child: const Text('start'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) {
            receivedExtra = state.extra;
            return const Scaffold(body: Text('chat destination'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('กลับสู่หน้าแชท'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('chat destination'), findsOneWidget);
    expect(receivedExtra, containsPair('initialIndex', 1));
    expect(
      receivedExtra,
      containsPair('message', 'เริ่มเช่าอุปกรณ์เรียบร้อยแล้ว'),
    );
  });
}
