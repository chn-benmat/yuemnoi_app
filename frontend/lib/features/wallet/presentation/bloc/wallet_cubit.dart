import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/wallet_transaction.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../domain/usecases/get_wallet_info_usecase.dart';
import '../../domain/usecases/pay_rental_with_wallet_usecase.dart';
import '../../domain/usecases/start_wallet_topup_usecase.dart';
import 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  WalletCubit({
    GetWalletInfoUseCase? getWalletInfo,
    StartWalletTopUpUseCase? startWalletTopUp,
    PayRentalWithWalletUseCase? payRentalWithWallet,
    WalletRepository? repository,
  })  : _getWalletInfo = getWalletInfo,
        _startWalletTopUp = startWalletTopUp,
        _payRentalWithWallet = payRentalWithWallet,
        _repository = repository,
        super(WalletState());

  final GetWalletInfoUseCase? _getWalletInfo;
  final StartWalletTopUpUseCase? _startWalletTopUp;
  final PayRentalWithWalletUseCase? _payRentalWithWallet;
  final WalletRepository? _repository;

  Future<void> fetchWallet() async {
    if (_getWalletInfo == null) return;
    emit(state.copyWith(status: WalletStatus.loading, clearError: true));
    try {
      final info = await _getWalletInfo.execute();
      emit(
        state.copyWith(
          balance: info.balance,
          currency: info.currency,
          transactions: info.transactions,
          status: WalletStatus.success,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: WalletStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<Uri?> startTopUp({required double amount}) async {
    if (amount <= 0) return null;
    emit(state.copyWith(status: WalletStatus.loading, clearError: true));
    try {
      if (_startWalletTopUp != null) {
        final checkout = await _startWalletTopUp.execute(amount);
        emit(
          state.copyWith(
            status: WalletStatus.success,
            topUpCheckoutUrl: checkout.checkoutUrl,
          ),
        );
        return checkout.checkoutUrl;
      }

      // If repository use case not injected, fallback to mock simulation
      final newTx = WalletTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: 'เติมเงินเข้าบัญชี',
        amount: amount,
        dateTime: DateTime.now(),
        status: 'เสร็จสิ้น',
      );
      emit(
        state.copyWith(
          balance: state.balance + amount,
          transactions: [newTx, ...state.transactions],
          status: WalletStatus.success,
        ),
      );
      return null;
    } catch (error) {
      emit(
        state.copyWith(
          status: WalletStatus.failure,
          errorMessage: error is WalletException ? error.message : 'ไม่สามารถเริ่มการเติมเงินได้',
        ),
      );
      return null;
    }
  }

  Future<void> topUp({
    required double amount,
    String paymentMethod = 'ธนาคาร',
  }) async {
    emit(state.copyWith(status: WalletStatus.loading));
    final newTx = WalletTransaction(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: 'โอนเข้าบัญชี',
      amount: amount,
      dateTime: DateTime.now(),
      status: 'เสร็จสิ้น',
    );
    emit(
      state.copyWith(
        balance: state.balance + amount,
        transactions: [newTx, ...state.transactions],
        status: WalletStatus.success,
      ),
    );
  }

  Future<void> onTopUpCompleted({required double amount}) async {
    final newTx = WalletTransaction(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: 'เติมเงินเข้าบัญชี (Stripe)',
      amount: amount,
      dateTime: DateTime.now(),
      status: 'เสร็จสิ้น',
    );
    emit(
      state.copyWith(
        balance: state.balance + amount,
        transactions: [newTx, ...state.transactions],
        status: WalletStatus.success,
        clearCheckoutUrl: true,
      ),
    );
    // Refresh from server
    await fetchWallet();
  }

  Future<bool> payRental({required int rentalId, required double amount}) async {
    if (state.balance < amount) {
      emit(
        state.copyWith(
          status: WalletStatus.failure,
          errorMessage: 'ยอดเงินในกระเป๋าไม่เพียงพอ',
        ),
      );
      return false;
    }

    emit(state.copyWith(status: WalletStatus.loading, clearError: true));
    try {
      if (_payRentalWithWallet != null) {
        final success = await _payRentalWithWallet.execute(rentalId);
        if (!success) {
          emit(
            state.copyWith(
              status: WalletStatus.failure,
              errorMessage: 'ไม่สามารถชำระเงินด้วยกระเป๋าเงินได้',
            ),
          );
          return false;
        }
      }

      final newTx = WalletTransaction(
        id: 'tx_pay_${DateTime.now().millisecondsSinceEpoch}',
        title: 'ชำระค่าเช่าอุปกรณ์ #$rentalId',
        amount: -amount,
        dateTime: DateTime.now(),
        type: 'rental_payment',
        status: 'เสร็จสิ้น',
      );

      emit(
        state.copyWith(
          balance: (state.balance - amount).clamp(0.0, double.infinity),
          transactions: [newTx, ...state.transactions],
          status: WalletStatus.success,
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          status: WalletStatus.failure,
          errorMessage: error is WalletException ? error.message : 'เกิดข้อผิดพลาดในการชำระเงิน',
        ),
      );
      return false;
    }
  }

  @override
  Future<void> close() {
    _repository?.close();
    return super.close();
  }
}
