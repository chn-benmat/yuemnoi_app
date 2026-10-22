import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/rental_management_repository_impl.dart';
import '../../domain/usecases/get_rental_bookings_usecase.dart';
import '../../domain/usecases/update_booking_status_usecase.dart';
import 'rental_status_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะคำขอเช่าและปล่อยเช่า รวมถึงการอัปเดตสถานะ (Handover/Return)
class RentalStatusCubit extends Cubit<RentalStatusState> {
  final GetRentalBookingsUseCase getRentalBookings;
  final UpdateBookingStatusUseCase updateBookingStatus;

  RentalStatusCubit({
    GetRentalBookingsUseCase? getRentalBookings,
    UpdateBookingStatusUseCase? updateBookingStatus,
  }) : getRentalBookings =
           getRentalBookings ??
           GetRentalBookingsUseCase(RentalManagementRepositoryImpl()),
       updateBookingStatus =
           updateBookingStatus ??
           UpdateBookingStatusUseCase(RentalManagementRepositoryImpl()),
       super(const RentalStatusInitial());

  Future<void> loadBookings(String userId) async {
    emit(const RentalStatusLoading());
    try {
      final renting = await getRentalBookings.executeRenting(userId);
      final lending = await getRentalBookings.executeLending(userId);

      bool isAllowedStatus(dynamic b) {
        final s = (b.statusCode ?? '').toString().toLowerCase().trim();
        return !{
          'rejected',
          'reject',
          'completed',
          'finished',
          'คืนของสำเร็จ',
        }.contains(s);
      }

      emit(
        RentalStatusLoaded(
          rentingList: renting.where(isAllowedStatus).toList(),
          lendingList: lending.where(isAllowedStatus).toList(),
        ),
      );
    } catch (e) {
      emit(RentalStatusError(e.toString()));
    }
  }

  Future<bool> changeStatus({
    required int bookingId,
    required String newStatus,
    required String userId,
  }) async {
    emit(const RentalStatusActionInProgress());
    try {
      await updateBookingStatus.execute(
        bookingId: bookingId,
        status: newStatus,
      );
      emit(const RentalStatusActionSuccess('อัปเดตสถานะสำเร็จ'));
      await loadBookings(userId);
      return true;
    } catch (e) {
      emit(RentalStatusError('เกิดข้อผิดพลาดในการอัปเดตสถานะ: $e'));
      return false;
    }
  }
}
