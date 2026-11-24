import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/rental_management_repository_impl.dart';
import '../../domain/usecases/get_rental_bookings_usecase.dart';
import '../../domain/usecases/update_booking_status_usecase.dart';
import 'rental_status_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะคำขอเช่าและปล่อยเช่า รวมถึงการอัปเดตสถานะ (Handover/Return)
class RentalStatusCubit extends Cubit<RentalStatusState> {
  Future<void>? _activeLoad;
  bool _reloadRequested = false;

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
    if (isClosed) return;

    final activeLoad = _activeLoad;
    if (activeLoad != null) {
      _reloadRequested = true;
      await activeLoad;
      return;
    }

    final load = _loadBookings(userId);
    _activeLoad = load;
    await load;
    if (identical(_activeLoad, load)) _activeLoad = null;

    if (_reloadRequested && !isClosed) {
      _reloadRequested = false;
      await loadBookings(userId);
    }
  }

  Future<void> _loadBookings(String userId) async {
    if (isClosed) return;
    emit(const RentalStatusLoading());
    try {
      final renting = await getRentalBookings.executeRenting(userId);
      if (isClosed) return;
      final lending = await getRentalBookings.executeLending(userId);
      if (isClosed) return;

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
      if (isClosed) return;
      emit(RentalStatusError(_userFacingError(e)));
    }
  }

  Future<bool> changeStatus({
    required int bookingId,
    required String newStatus,
    required String userId,
  }) async {
    if (isClosed || state is RentalStatusActionInProgress) return false;
    emit(const RentalStatusActionInProgress());
    try {
      await updateBookingStatus.execute(
        bookingId: bookingId,
        status: newStatus,
      );
      if (isClosed) return false;
      emit(const RentalStatusActionSuccess('อัปเดตสถานะสำเร็จ'));
      await loadBookings(userId);
      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(
        RentalStatusError(
          'เกิดข้อผิดพลาดในการอัปเดตสถานะ: ${_userFacingError(e)}',
        ),
      );
      return false;
    }
  }

  String _userFacingError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '');
  }
}
