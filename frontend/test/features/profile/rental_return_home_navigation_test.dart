import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/rental_return/domain/entities/rental_return_session.dart';
import 'package:frontend/features/rental_return/domain/repositories/rental_return_repository.dart';
import 'package:frontend/features/rental_return/presentation/pages/rental_return_page.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements RentalReturnRepository {}

void main() {
  setUpAll(() => initializeDateFormatting('th'));

  for (final isLender in [false, true]) {
    testWidgets(
      '${isLender ? 'lender' : 'renter'} returns home after completing return',
      (tester) async {
        final repository = _Repository();
        final session = RentalReturnSession.createMockSession().copyWith(
          step: RentalReturnStep.completed,
        );
        when(
          () => repository.getReturnSession(any()),
        ).thenAnswer((_) async => session);
        Object? destination;
        final router = GoRouter(
          initialLocation: '/return',
          routes: [
            GoRoute(
              path: '/return',
              builder: (_, _) =>
                  RentalReturnPage(isLender: isLender, repository: repository),
            ),
            GoRoute(
              path: AppRoutes.home,
              builder: (_, state) {
                destination = state.extra;
                return const Scaffold(body: Text('หน้าหลักทดสอบ'));
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsOneWidget);
        await tester.tap(find.text('เสร็จสิ้น'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('หน้าหลักทดสอบ'), findsOneWidget);
        expect(destination, 0);
      },
    );
  }
}
