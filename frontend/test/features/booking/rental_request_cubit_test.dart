import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/domain/entities/rental_request.dart';
import 'package:frontend/features/booking/domain/repositories/rental_request_repository.dart';
import 'package:frontend/features/booking/domain/usecases/submit_rental_request_usecase.dart';
import 'package:frontend/features/booking/presentation/bloc/rental_request_cubit.dart';
import 'package:frontend/features/booking/presentation/bloc/rental_request_state.dart';
import 'package:frontend/features/booking/presentation/pages/booking_confirmation_page.dart';

class FakeRentalRequestRepository implements RentalRequestRepository {
  RentalRequestResult? result;
  Object? error;
  int submitCalls = 0;

  @override
  Future<RentalRequestResult> submit(RentalRequestDraft draft) async {
    submitCalls++;
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

RentalRequestCubit buildCubit(FakeRentalRequestRepository repository) {
  return RentalRequestCubit(
    submitRentalRequest: SubmitRentalRequestUseCase(repository),
    repository: repository,
  );
}

void main() {
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
      RentalRequestState(status: RentalRequestStatus.success, rentalId: 21),
    ],
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

  testWidgets('confirmation submits a rental request without payment options', (
    tester,
  ) async {
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: BookingConfirmationPage(bookingData: bookingData),
        ),
      ),
    );

    expect(find.text('ส่งคำขอเช่า'), findsOneWidget);
    expect(find.text('วิธีการชำระเงิน'), findsNothing);
    expect(find.textContaining('Stripe'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('submit-rental-request-button')),
    );
    await tester.pump();

    expect(repository.submitCalls, 1);
  });
}
