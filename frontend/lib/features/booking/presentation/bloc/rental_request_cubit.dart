import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../identity/domain/rental_verification.dart';
import '../../domain/entities/rental_request.dart';
import '../../domain/repositories/rental_request_repository.dart';
import '../../domain/usecases/confirm_rental_request_usecase.dart';
import '../../domain/usecases/submit_rental_request_usecase.dart';
import 'rental_request_state.dart';

class RentalRequestCubit extends Cubit<RentalRequestState> {
  RentalRequestCubit({
    required SubmitRentalRequestUseCase submitRentalRequest,
    required RentalRequestRepository repository,
    ConfirmRentalRequestUseCase? confirmRentalRequest,
  }) : _submitRentalRequest = submitRentalRequest,
       _confirmRentalRequest =
           confirmRentalRequest ?? ConfirmRentalRequestUseCase(repository),
       _repository = repository,
       super(const RentalRequestState());

  final SubmitRentalRequestUseCase _submitRentalRequest;
  final ConfirmRentalRequestUseCase _confirmRentalRequest;
  final RentalRequestRepository _repository;

  Future<bool> submit(RentalRequestDraft draft) async {
    if (state.status == RentalRequestStatus.submitting ||
        state.rentalId != null)
      return false;
    emit(const RentalRequestState(status: RentalRequestStatus.submitting));
    try {
      final result = await _submitRentalRequest.execute(draft);
      if (isClosed) return false;
      emit(
        RentalRequestState(
          status: RentalRequestStatus.success,
          rentalId: result.id,
          rentalStatus: result.status,
        ),
      );
      return true;
    } on RentalVerificationRequired catch (error) {
      if (isClosed) return false;
      emit(
        RentalRequestState(
          status: RentalRequestStatus.failure,
          verification: error.verification,
        ),
      );
      return false;
    } on RentalRequestException catch (error) {
      if (isClosed) return false;
      emit(
        RentalRequestState(
          status: RentalRequestStatus.failure,
          errorMessage: error.message,
        ),
      );
      return false;
    } catch (_) {
      if (isClosed) return false;
      emit(
        const RentalRequestState(
          status: RentalRequestStatus.failure,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        ),
      );
      return false;
    }
  }

  Future<bool> confirm({
    required String offerMessageId,
    required String paymentMethod,
    int? rentalId,
    int? requestRevision,
  }) async {
    final id = rentalId ?? state.rentalId;
    if (id == null ||
        state.status == RentalRequestStatus.confirming ||
        state.status == RentalRequestStatus.confirmed)
      return false;
    final rentalStatus = state.rentalStatus;
    emit(
      RentalRequestState(
        status: RentalRequestStatus.confirming,
        rentalId: id,
        rentalStatus: rentalStatus,
      ),
    );
    try {
      final result = await _confirmRentalRequest.execute(
        rentalId: id,
        offerMessageId: offerMessageId,
        paymentMethod: paymentMethod,
        requestRevision: requestRevision,
      );
      if (isClosed) return false;
      emit(
        RentalRequestState(
          status: RentalRequestStatus.confirmed,
          rentalId: id,
          rentalStatus: result.status,
        ),
      );
      return true;
    } catch (error) {
      if (isClosed) return false;
      emit(
        RentalRequestState(
          status: RentalRequestStatus.failure,
          rentalId: id,
          rentalStatus: rentalStatus,
          errorMessage: error is RentalRequestException
              ? error.message
              : 'ยืนยันการเช่าไม่สำเร็จ กรุณาลองใหม่',
        ),
      );
      return false;
    }
  }

  @override
  Future<void> close() {
    _repository.close();
    return super.close();
  }
}
