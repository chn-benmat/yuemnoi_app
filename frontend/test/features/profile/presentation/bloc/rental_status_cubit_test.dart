import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/rental_booking.dart';
import 'package:frontend/features/profile/domain/usecases/get_rental_bookings_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_booking_status_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/rental_status_cubit.dart';
import 'package:frontend/features/profile/presentation/bloc/rental_status_state.dart';

import '../../domain/usecases/rental_usecases_test.dart';

RentalStatusCubit buildCubit(FakeRentalManagementRepository repository) {
  return RentalStatusCubit(
    getRentalBookings: GetRentalBookingsUseCase(repository),
    updateBookingStatus: UpdateBookingStatusUseCase(repository),
  );
}

void main() {
  group('RentalStatusCubit', () {
    test(
      'completed returns disappear from both roles but pending returns remain',
      () async {
        final repo = FakeRentalManagementRepository();
        final bookings = [
          for (final status in [
            'completed',
            'finished',
            'active',
            'awaiting_return',
            'return_ready',
          ])
            RentalBooking(
              bookingId: status.length,
              title: status,
              partnerName: 'Partner',
              partnerRole: 'Owner',
              status: status,
              statusCode: status,
            ),
        ];
        repo.rentingList
          ..clear()
          ..addAll(bookings);
        repo.lendingList
          ..clear()
          ..addAll(bookings);
        final cubit = buildCubit(repo);
        await cubit.loadBookings('user1');
        final state = cubit.state as RentalStatusLoaded;
        expect(state.rentingList.map((b) => b.statusCode), [
          'active',
          'awaiting_return',
          'return_ready',
        ]);
        expect(state.lendingList.map((b) => b.statusCode), [
          'active',
          'awaiting_return',
          'return_ready',
        ]);
        await cubit.close();
      },
    );

    test('initial state is RentalStatusInitial', () {
      final repository = FakeRentalManagementRepository();
      final cubit = buildCubit(repository);
      expect(cubit.state, isA<RentalStatusInitial>());
      cubit.close();
    });

    blocTest<RentalStatusCubit, RentalStatusState>(
      'loadBookings emits [RentalStatusLoading, RentalStatusLoaded]',
      build: () => buildCubit(FakeRentalManagementRepository()),
      act: (cubit) => cubit.loadBookings('user1'),
      expect: () => [
        isA<RentalStatusLoading>(),
        isA<RentalStatusLoaded>()
            .having((s) => s.rentingList.length, 'rentingList length', 1)
            .having((s) => s.lendingList.length, 'lendingList length', 1),
      ],
    );

    blocTest<RentalStatusCubit, RentalStatusState>(
      'changeStatus emits [RentalStatusActionInProgress, RentalStatusActionSuccess, RentalStatusLoading, RentalStatusLoaded]',
      build: () => buildCubit(FakeRentalManagementRepository()),
      act: (cubit) => cubit.changeStatus(
        bookingId: 10,
        newStatus: 'active',
        userId: 'user1',
      ),
      expect: () => [
        isA<RentalStatusActionInProgress>(),
        isA<RentalStatusActionSuccess>(),
        isA<RentalStatusLoading>(),
        isA<RentalStatusLoaded>(),
      ],
    );

    blocTest<RentalStatusCubit, RentalStatusState>(
      'loadBookings keeps pending and confirmed but filters rejected bookings',
      build: () {
        final repo = FakeRentalManagementRepository();
        repo.rentingList.clear();
        repo.rentingList.addAll([
          const RentalBooking(
            bookingId: 101,
            title: 'Pending Item',
            partnerName: 'Owner 1',
            partnerRole: 'เจ้าของอุปกรณ์',
            status: 'รอเจ้าของยืนยัน',
            statusCode: 'pending',
          ),
          const RentalBooking(
            bookingId: 102,
            title: 'Rejected Item',
            partnerName: 'Owner 2',
            partnerRole: 'เจ้าของอุปกรณ์',
            status: 'ถูกปฏิเสธ',
            statusCode: 'rejected',
          ),
          const RentalBooking(
            bookingId: 103,
            title: 'Confirmed Item',
            partnerName: 'Owner 3',
            partnerRole: 'เจ้าของอุปกรณ์',
            status: 'ยืนยันแล้ว / นัดรับของ',
            statusCode: 'confirmed',
          ),
        ]);
        return buildCubit(repo);
      },
      act: (cubit) => cubit.loadBookings('user1'),
      expect: () => [
        isA<RentalStatusLoading>(),
        isA<RentalStatusLoaded>()
            .having((s) => s.rentingList.length, 'rentingList length', 2)
            .having((s) => s.rentingList.last.bookingId, 'last bookingId', 103),
      ],
    );
  });
}
