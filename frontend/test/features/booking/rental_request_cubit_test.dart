import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/booking/data/datasources/rental_request_remote_data_source.dart';
import 'package:frontend/features/booking/data/repositories/rental_request_repository_impl.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/domain/entities/rental_request.dart';
import 'package:frontend/features/booking/domain/repositories/rental_request_repository.dart';
import 'package:frontend/features/booking/domain/usecases/submit_rental_request_usecase.dart';
import 'package:frontend/features/booking/presentation/bloc/rental_request_cubit.dart';
import 'package:frontend/features/booking/presentation/bloc/rental_request_state.dart';
import 'package:frontend/features/booking/presentation/pages/booking_confirmation_page.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRentalApiClient extends Mock implements ApiClient {}

class FakeRentalRequestRepository implements RentalRequestRepository {
  RentalRequestResult? result;
  Object? error;
  int submitCalls = 0;
  RentalRequestDraft? lastDraft;
  int confirmCalls = 0;
  int? confirmedRentalId;
  String? confirmedOfferMessageId;
  Object? confirmError;
  Completer<RentalRequestResult>? confirmation;

  @override
  Future<RentalRequestResult> confirm({
    required int rentalId,
    required String offerMessageId,
    required String paymentMethod,
    int? requestRevision,
  }) async {
    confirmCalls++;
    confirmedRentalId = rentalId;
    confirmedOfferMessageId = offerMessageId;
    if (confirmError != null) throw confirmError!;
    return confirmation == null
        ? RentalRequestResult(id: rentalId, status: 'confirmed')
        : confirmation!.future;
  }

  @override
  Future<RentalRequestResult> submit(RentalRequestDraft draft) async {
    submitCalls++;
    lastDraft = draft;
    final submitError = error;
    if (submitError != null) throw submitError;
    return result!;
  }

  @override
  void close() {}
}

final draft = RentalRequestDraft(
  itemId: 7,
  startAt: DateTime.utc(2026, 9, 5, 2),
  endAt: DateTime.utc(2026, 9, 6, 2),
  rentalType: 'daily',
  pickupLocation: 'บางแค',
);

RentalRequestCubit buildCubit(RentalRequestRepository repository) {
  return RentalRequestCubit(
    submitRentalRequest: SubmitRentalRequestUseCase(repository),
    repository: repository,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingConfirmationTracker.clearMemoryCache();
  });

  test(
    'owner confirms the existing customer booking without submission',
    () async {
      final repository = FakeRentalRequestRepository();
      final cubit = buildCubit(repository);
      addTearDown(cubit.close);

      expect(
        await cubit.confirm(
          rentalId: 25,
          offerMessageId: '36',
          paymentMethod: '',
        ),
        isTrue,
      );
      expect(cubit.state.status, RentalRequestStatus.confirmed);
      expect(repository.confirmedRentalId, 25);
      expect(repository.confirmedOfferMessageId, '36');
      expect(repository.submitCalls, 0);
    },
  );

  testWidgets('a blocked rental opens the checklist and its contact page', (
    tester,
  ) async {
    final client = MockRentalApiClient();
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    when(
      () => client.post(
        '/api/rentals',
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 403,
        data: {
          'code': 'rental_verification_required',
          'error': 'กรุณายืนยันข้อมูลก่อนทำรายการ',
          'rental_verification': {
            'id_card_approved': false,
            'contact_phone_saved': false,
            'identity_pending': true,
          },
        },
      ),
    );
    final cubit = buildCubit(
      RentalRequestRepositoryImpl(
        RentalRequestRemoteDataSource(client: client),
      ),
    );
    addTearDown(cubit.close);
    final booking = BookingRequestData(
      item: const BookingItemInfo(
        id: 7,
        title: 'อุปกรณ์ทดสอบ',
        imageUrl: '',
        rating: 0,
        reviewCount: 0,
        hourlyRate: 100,
        dailyRate: 500,
        defaultLocation: 'บางแค',
      ),
      startDate: draft.startAt,
      endDate: draft.endAt,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: draft.pickupLocation,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider.value(
            value: cubit,
            child: BookingConfirmationPage(bookingData: booking),
          ),
        ),
        GoRoute(
          path: AppRoutes.editContact,
          builder: (_, _) => const Scaffold(body: Text('หน้าบันทึกเบอร์')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(
      find.byKey(const ValueKey('submit-rental-request-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('บัตรประชาชนอยู่ระหว่างตรวจสอบ'), findsOneWidget);
    expect(find.text('เพิ่มเบอร์โทรศัพท์'), findsOneWidget);
    expect(cubit.state.rentalId, isNull);

    await tester.tap(find.text('เพิ่มเบอร์โทรศัพท์'));
    await tester.pumpAndSettle();
    expect(find.text('หน้าบันทึกเบอร์'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookingConfirmationPage), findsOneWidget);
  });

  blocTest<RentalRequestCubit, RentalRequestState>(
    'emits submitting and success when request is created',
    build: () {
      final repository = FakeRentalRequestRepository()
        ..result = const RentalRequestResult(id: 21, status: 'pending');
      return buildCubit(repository);
    },
    act: (cubit) => cubit.submit(draft),
    expect: () => const [
      RentalRequestState(status: RentalRequestStatus.submitting),
      RentalRequestState(
        status: RentalRequestStatus.success,
        rentalId: 21,
        rentalStatus: 'pending',
      ),
    ],
  );

  test(
    'confirmation failure retries the same pending booking without resubmission',
    () async {
      final repository = FakeRentalRequestRepository()
        ..result = const RentalRequestResult(id: 21, status: 'pending')
        ..confirmError = const RentalRequestException('ยืนยันไม่สำเร็จ');
      final cubit = buildCubit(repository);
      addTearDown(cubit.close);
      await cubit.submit(draft);
      expect(cubit.state.status, RentalRequestStatus.success);
      expect(repository.confirmCalls, 0);
      expect(
        await cubit.confirm(offerMessageId: '11', paymentMethod: 'cash'),
        isFalse,
      );
      expect(cubit.state.rentalId, 21);
      expect(cubit.state.status, RentalRequestStatus.failure);
      repository.confirmError = null;
      expect(
        await cubit.confirm(offerMessageId: '11', paymentMethod: 'cash'),
        isTrue,
      );
      expect(cubit.state.status, RentalRequestStatus.confirmed);
      expect(cubit.state.rentalStatus, 'confirmed');
      expect(
        await cubit.confirm(offerMessageId: '11', paymentMethod: 'cash'),
        isFalse,
      );
      expect(repository.submitCalls, 1);
      expect(repository.confirmCalls, 2);
      expect(repository.confirmedRentalId, 21);
      expect(repository.confirmedOfferMessageId, '11');
    },
  );

  test(
    'repeated taps send one confirmation and a pending response is not success',
    () async {
      final repository = FakeRentalRequestRepository()
        ..result = const RentalRequestResult(id: 21, status: 'pending')
        ..confirmation = Completer<RentalRequestResult>();
      final cubit = buildCubit(repository);
      addTearDown(cubit.close);
      await cubit.submit(draft);
      final first = cubit.confirm(offerMessageId: '11', paymentMethod: 'cash');
      expect(cubit.state.status, RentalRequestStatus.confirming);
      expect(
        await cubit.confirm(offerMessageId: '11', paymentMethod: 'cash'),
        isFalse,
      );
      expect(repository.confirmCalls, 1);
      repository.confirmation!.complete(
        const RentalRequestResult(id: 21, status: 'pending'),
      );
      expect(await first, isFalse);
      expect(cubit.state.status, RentalRequestStatus.failure);
      expect(cubit.state.rentalId, 21);
    },
  );

  blocTest<RentalRequestCubit, RentalRequestState>(
    'shows repository message when submission fails',
    build: () {
      final repository = FakeRentalRequestRepository()
        ..error = const RentalRequestException('ช่วงเวลานี้ไม่ว่าง');
      return buildCubit(repository);
    },
    act: (cubit) => cubit.submit(draft),
    expect: () => const [
      RentalRequestState(status: RentalRequestStatus.submitting),
      RentalRequestState(
        status: RentalRequestStatus.failure,
        errorMessage: 'ช่วงเวลานี้ไม่ว่าง',
      ),
    ],
  );

  testWidgets(
    'renter can submit the same queue offer after the owner updates its start',
    (tester) async {
      final repository = FakeRentalRequestRepository()
        ..result = const RentalRequestResult(id: 21, status: 'pending');
      final cubit = buildCubit(repository);
      addTearDown(cubit.close);
      final start = DateTime.now().subtract(const Duration(days: 2));
      final offer = BookingRequestData(
        item: const BookingItemInfo(
          id: 7,
          title: 'อุปกรณ์ทดสอบ',
          imageUrl: '',
          rating: 0,
          reviewCount: 0,
          hourlyRate: 100,
          dailyRate: 500,
          defaultLocation: 'บางแค',
        ),
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        location: 'บางแค',
        originalMessageId: '663',
        rentalQueueMessageId: 660,
      );
      Future<void> openOffer(BookingRequestData data) => tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: BookingConfirmationPage(
              key: ValueKey(data.startDate),
              bookingData: data,
            ),
          ),
        ),
      );
      await openOffer(offer);
      final submit = find.byKey(const ValueKey('submit-rental-request-button'));
      await tester.tap(submit);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.submitCalls, 0);
      expect(
        find.text(
          'เวลาเริ่มเช่าผ่านไปแล้ว กรุณาให้เจ้าของแก้ไขรายละเอียดบนการ์ดข้อเสนอในแชท',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();

      final futureDate = DateTime.now().add(const Duration(days: 2));
      final revisedOffer = offer.copyWith(
        startDate: futureDate,
        endDate: futureDate.add(const Duration(days: 1)),
      );
      await openOffer(revisedOffer);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.submitCalls, 1);
      expect(repository.lastDraft?.offerMessageId, '663');
      expect(repository.lastDraft?.startAt, revisedOffer.startDateTime);
    },
  );

  testWidgets(
    'confirmation submits the owner offer and preserves an existing booking',
    (tester) async {
      final repository = FakeRentalRequestRepository()
        ..result = const RentalRequestResult(id: 21, status: 'pending');
      final cubit = buildCubit(repository);
      addTearDown(cubit.close);
      final start = DateTime(2026, 9, 5);
      final bookingData = BookingRequestData(
        item: const BookingItemInfo(
          id: 7,
          title: 'กล้องทดสอบ',
          imageUrl: '',
          rating: 5,
          reviewCount: 1,
          hourlyRate: 100,
          dailyRate: 500,
          defaultLocation: 'บางแค',
        ),
        startDate: start,
        endDate: start.add(const Duration(days: 1)),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        location: 'บางแค',
        originalMessageId: '11',
        bookingId: 25,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: BookingConfirmationPage(bookingData: bookingData),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('submit-rental-request-button')),
          matching: find.text('ยืนยันคำขอเช่า'),
        ),
        findsOneWidget,
      );
      expect(find.text('วิธีการชำระเงิน'), findsNothing);
      expect(find.textContaining('Stripe'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('submit-rental-request-button')),
      );
      await tester.pump();

      expect(repository.submitCalls, 1);
      expect(repository.lastDraft?.offerMessageId, '11');
      expect(repository.lastDraft?.bookingId, 25);
      await tester.pumpAndSettle();
      expect(
        await BookingConfirmationTracker.isConfirmed(messageId: '11'),
        isFalse,
        reason: 'Opening the summary must not confirm the rental',
      );
      expect(
        find.byKey(const ValueKey('confirm-rental-button')),
        findsOneWidget,
      );
      expect(repository.confirmCalls, 0);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('confirm-rental-button'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        await BookingConfirmationTracker.isConfirmed(messageId: '11'),
        isFalse,
      );
      expect(cubit.state.status, RentalRequestStatus.success);
      await tester.ensureVisible(
        find.byKey(const ValueKey('submit-rental-request-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('submit-rental-request-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('confirm-rental-button')),
        findsOneWidget,
      );
      expect(repository.submitCalls, 1);
      repository.confirmError = const RentalRequestException(
        'ลองยืนยันอีกครั้ง',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-rental-button')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-rental-button')));
      await tester.pumpAndSettle();
      expect(find.text('ลองยืนยันอีกครั้ง'), findsOneWidget);
      expect(
        await BookingConfirmationTracker.isConfirmed(messageId: '11'),
        isFalse,
      );
      expect(repository.submitCalls, 1);
    },
  );

  testWidgets('confirming PromptPay sends it before returning to chat', (
    tester,
  ) async {
    final client = MockRentalApiClient();
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    when(
      () => client.post(
        '/api/rentals',
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 201,
        data: {'id': 21, 'status': 'pending'},
      ),
    );
    when(
      () => client.post(
        '/api/rentals/21/confirm',
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'id': 21, 'status': 'confirmed', 'payment_method': 'promptpay'},
      ),
    );
    final cubit = buildCubit(
      RentalRequestRepositoryImpl(
        RentalRequestRemoteDataSource(client: client),
      ),
    );
    addTearDown(cubit.close);
    final booking = BookingRequestData(
      item: const BookingItemInfo(
        id: 7,
        title: 'Test camera',
        imageUrl: '',
        rating: 5,
        reviewCount: 1,
        hourlyRate: 100,
        dailyRate: 500,
        defaultLocation: 'Pickup',
      ),
      startDate: DateTime(2026, 10, 18),
      endDate: DateTime(2026, 10, 19),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: 'Pickup',
      originalMessageId: '11',
    );
    bool? confirmed;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () async {
                confirmed = await AppRoutes.openBookingConfirmation(
                  context,
                  bookingData: booking,
                );
              },
              child: const Text('open confirmation'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.bookingConfirmation,
          builder: (_, state) => BlocProvider.value(
            value: cubit,
            child: BookingConfirmationPage(
              bookingData: state.extra as BookingRequestData,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open confirmation'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('PromptPay'));
    await tester.tap(find.text('PromptPay'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-rental-request-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('submit-rental-request-button')),
    );
    await tester.pumpAndSettle();
    verifyNever(
      () => client.post(
        '/api/rentals/21/confirm',
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    );
    expect(
      await BookingConfirmationTracker.isConfirmed(messageId: '11'),
      isFalse,
    );
    expect(find.text('ตรวจสอบสถานะการเช่า'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-rental-button')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-rental-button')));
    await tester.pumpAndSettle();
    final confirmationBody = verify(
      () => client.post(
        '/api/rentals/21/confirm',
        data: captureAny(named: 'data'),
        headers: {'Authorization': 'Bearer test-token'},
      ),
    ).captured.single;
    expect(confirmationBody, {
      'offer_message_id': '11',
      'payment_method': 'promptpay',
    });
    expect(tester.takeException(), isNull);
    expect(confirmed, isTrue);
    expect(find.text('open confirmation'), findsOneWidget);
    expect(
      await BookingConfirmationTracker.isConfirmed(messageId: '11'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
