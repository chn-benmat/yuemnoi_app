import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/usecases/get_payment_status_usecase.dart';
import '../../domain/usecases/start_payment_usecase.dart';
import 'payment_state.dart';

class PaymentCubit extends Cubit<PaymentState> {
  PaymentCubit({
    required StartPaymentUseCase startPayment,
    required GetPaymentStatusUseCase getPaymentStatus,
    required PaymentRepository repository,
    int? initialRentalId,
  }) : _startPayment = startPayment,
       _getPaymentStatus = getPaymentStatus,
       _repository = repository,
       super(PaymentState(rentalId: initialRentalId));

  final StartPaymentUseCase _startPayment;
  final GetPaymentStatusUseCase _getPaymentStatus;
  final PaymentRepository _repository;

  Future<Uri?> start(PaymentRentalDraft draft) async {
    if (state.flowStatus == PaymentFlowStatus.creatingCheckout) return null;
    emit(
      state.copyWith(
        flowStatus: PaymentFlowStatus.creatingCheckout,
        clearError: true,
      ),
    );
    try {
      final checkout = await _startPayment.execute(draft);
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.awaitingPayment,
          rentalId: checkout.rentalId,
          checkoutUrl: checkout.checkoutUrl,
          providerStatus: checkout.status,
        ),
      );
      return checkout.checkoutUrl;
    } on PaymentException catch (error) {
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.failed,
          errorMessage: error.message,
        ),
      );
      return null;
    } catch (_) {
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.failed,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        ),
      );
      return null;
    }
  }

  Future<bool> payWithWallet(PaymentRentalDraft draft) async {
    if (state.flowStatus == PaymentFlowStatus.creatingCheckout) return false;
    emit(
      state.copyWith(
        flowStatus: PaymentFlowStatus.creatingCheckout,
        clearError: true,
      ),
    );
    try {
      final rentalId = await _repository.createRental(draft);
      final success = await _repository.payWithWallet(rentalId);
      if (success) {
        emit(
          state.copyWith(
            flowStatus: PaymentFlowStatus.paid,
            rentalId: rentalId,
          ),
        );
        return true;
      } else {
        emit(
          state.copyWith(
            flowStatus: PaymentFlowStatus.failed,
            errorMessage: 'ไม่สามารถชำระเงินด้วยกระเป๋าเงินได้',
          ),
        );
        return false;
      }
    } on PaymentException catch (error) {
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.failed,
          errorMessage: error.message,
        ),
      );
      return false;
    } catch (_) {
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.failed,
          errorMessage: 'เกิดข้อผิดพลาดในการชำระเงิน กรุณาลองใหม่',
        ),
      );
      return false;
    }
  }

  Future<void> refresh({int? rentalId}) async {
    final targetRentalId = rentalId ?? state.rentalId;
    if (targetRentalId == null ||
        state.flowStatus == PaymentFlowStatus.checkingStatus) {
      return;
    }
    emit(
      state.copyWith(
        flowStatus: PaymentFlowStatus.checkingStatus,
        rentalId: targetRentalId,
        clearError: true,
      ),
    );
    try {
      final payment = await _getPaymentStatus.execute(targetRentalId);
      emit(
        state.copyWith(
          flowStatus: payment.isPaid
              ? PaymentFlowStatus.paid
              : payment.isTerminalFailure
              ? PaymentFlowStatus.failed
              : PaymentFlowStatus.awaitingPayment,
          providerStatus: payment.status,
          errorMessage: payment.isTerminalFailure
              ? 'การชำระเงินไม่สำเร็จ กรุณาเริ่มรายการใหม่'
              : null,
        ),
      );
    } on PaymentException catch (error) {
      emit(
        state.copyWith(
          flowStatus: PaymentFlowStatus.failed,
          errorMessage: error.message,
        ),
      );
    }
  }

  void markLaunchFailed() {
    emit(
      state.copyWith(
        flowStatus: PaymentFlowStatus.failed,
        errorMessage: 'ไม่สามารถเปิดหน้าชำระเงินของ Stripe ได้',
      ),
    );
  }

  @override
  Future<void> close() {
    _repository.close();
    return super.close();
  }
}
