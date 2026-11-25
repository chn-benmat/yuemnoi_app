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

  for (final (scenario, startsCompleted, showsAlarm) in [
    ('when the return becomes confirmed', false, false),
    ('when the return is already confirmed', true, false),
    ('when the return is confirmed while the reminder is open', false, true),
  ]) {
    testWidgets('renter opens the review $scenario', (tester) async {
      Future<void> pumpRoute() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
      }

      final repository = _Repository();
      var session = _returnSession(
        itemId: 7,
        nearDeadline: showsAlarm,
        step: startsCompleted
            ? RentalReturnStep.completed
            : RentalReturnStep.inProgress,
      );
      when(() => repository.getReturnSession(25)).thenAnswer((_) async {
        return session;
      });
      Object? reviewArguments;
      final router = GoRouter(
        initialLocation: '/return',
        routes: [
          GoRoute(
            path: '/return',
            builder: (_, _) => RentalReturnPage(
              rentalId: 25,
              isLender: false,
              repository: repository,
            ),
          ),
          GoRoute(
            path: AppRoutes.review,
            builder: (_, state) {
              reviewArguments = state.extra;
              return const Scaffold(body: Text('หน้ารีวิวทดสอบ'));
            },
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('หน้าหลักทดสอบ')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await pumpRoute();

      if (!startsCompleted) {
        if (showsAlarm) {
          expect(find.text('ใกล้ถึงเวลาคืนอุปกรณ์แล้ว!'), findsOneWidget);
        } else {
          expect(find.text('นำสินค้าไปส่งที่จุดคืนตามนัด'), findsOneWidget);
        }
        expect(find.text('หน้ารีวิวทดสอบ'), findsNothing);
        session = session.copyWith(step: RentalReturnStep.completed);
        await tester.pump(const Duration(seconds: 10));
        await pumpRoute();
      }

      expect(find.text('หน้ารีวิวทดสอบ'), findsOneWidget);
      expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsNothing);
      expect(
        find.text('ใกล้ถึงเวลาคืนอุปกรณ์แล้ว!', skipOffstage: false),
        findsNothing,
      );
      expect(reviewArguments, {
        'bookingId': 25,
        'itemId': 7,
        'itemName': 'กล้องทดสอบ',
        'itemImageUrl': 'https://example.test/camera.png',
        'ownerId': 'lender',
        'ownerName': 'ร้านทดสอบ',
      });

      await tester.pump(const Duration(seconds: 20));
      await pumpRoute();
      verify(
        () => repository.getReturnSession(25),
      ).called(startsCompleted ? 1 : 2);
      router.pop();
      await pumpRoute();
      expect(find.text('หน้าหลักทดสอบ'), findsOneWidget);
    });
  }

  for (final isLender in [false, true]) {
    testWidgets(
      isLender
          ? 'lender returns home after completing return'
          : 'renter can finish a completed return with no item to review',
      (tester) async {
        final repository = _Repository();
        final session = _returnSession(
          itemId: isLender ? 7 : null,
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

RentalReturnSession _returnSession({
  required int? itemId,
  required RentalReturnStep step,
  bool nearDeadline = false,
}) {
  final now = DateTime.now();
  return RentalReturnSession(
    rentalId: 25,
    itemId: itemId,
    itemName: 'กล้องทดสอบ',
    itemImageUrl: 'https://example.test/camera.png',
    category: 'กล้อง',
    renterId: 'renter',
    renterName: 'ผู้เช่าทดสอบ',
    lenderId: 'lender',
    lenderName: 'ร้านทดสอบ',
    lenderPhone: '',
    startAt: now.subtract(const Duration(days: 1)),
    endAt: now.add(Duration(minutes: nearDeadline ? 30 : 120)),
    pickupLocation: '',
    totalPrice: 100,
    depositAmount: 0,
    step: step,
  );
}
