import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/rental_request.dart';
import '../../domain/repositories/rental_request_repository.dart';
import '../../domain/usecases/submit_rental_request_usecase.dart';
import 'rental_request_state.dart';

class RentalRequestCubit extends Cubit<RentalRequestState> {
  RentalRequestCubit({
    required SubmitRentalRequestUseCase submitRentalRequest,
    required RentalRequestRepository repository,
  }) : _submitRentalRequest = submitRentalRequest,
       _repository = repository,
       super(const RentalRequestState());

  final SubmitRentalRequestUseCase _submitRentalRequest;
  final RentalRequestRepository _repository;

  Future<bool> submit(RentalRequestDraft draft) async {
    if (state.status == RentalRequestStatus.submitting) return false;
    emit(const RentalRequestState(status: RentalRequestStatus.submitting));
    try {
      final result = await _submitRentalRequest.execute(draft);
      emit(
        RentalRequestState(
          status: RentalRequestStatus.success,
          rentalId: result.id,
        ),
      );
      return true;
    } on RentalRequestException catch (error) {
      emit(
        RentalRequestState(
          status: RentalRequestStatus.failure,
          errorMessage: error.message,
        ),
      );
      return false;
    } catch (_) {
      emit(
        const RentalRequestState(
          status: RentalRequestStatus.failure,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
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
