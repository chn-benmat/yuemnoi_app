import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
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
        isA<RentalStatusLoaded>().having(
          (s) => s.rentingList.length,
          'rentingList length',
          1,
        ).having(
          (s) => s.lendingList.length,
          'lendingList length',
          1,
        ),
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
  });
}
