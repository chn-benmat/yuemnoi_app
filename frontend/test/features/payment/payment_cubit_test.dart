import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/payment/domain/entities/payment.dart';
import 'package:frontend/features/payment/domain/repositories/payment_repository.dart';
import 'package:frontend/features/payment/domain/usecases/get_payment_status_usecase.dart';
import 'package:frontend/features/payment/domain/usecases/start_payment_usecase.dart';
import 'package:frontend/features/payment/presentation/bloc/payment_cubit.dart';
import 'package:frontend/features/payment/presentation/bloc/payment_state.dart';

class _PaymentRepositoryFake implements PaymentRepository {
  PaymentCheckout? checkout;
  RentalPaymentStatus? paymentStatus;
  PaymentException? startError;
  bool closed = false;

  @override
  Future<PaymentCheckout> startCheckout(PaymentRentalDraft draft) async {
    final error = startError;
    if (error != null) throw error;
    return checkout!;
  }

  @override
  Future<int> createRental(PaymentRentalDraft draft) async => 21;

  @override
  Future<bool> payWithWallet(int rentalId) async => true;

  @override
  Future<RentalPaymentStatus> getStatus(int rentalId) async => paymentStatus!;

  @override
  void close() => closed = true;
}

PaymentCubit _cubit(_PaymentRepositoryFake repository) => PaymentCubit(
  startPayment: StartPaymentUseCase(repository),
  getPaymentStatus: GetPaymentStatusUseCase(repository),
  repository: repository,
);

final _draft = PaymentRentalDraft(
  itemId: 7,
  startAt: DateTime.utc(2026, 9, 5, 2),
  endAt: DateTime.utc(2026, 9, 6, 2),
  rentalType: 'daily',
  pickupLocation: 'บางแค',
);

void main() {
  blocTest<PaymentCubit, PaymentState>(
    'เก็บ rental id และรอ webhook หลังสร้าง Checkout สำเร็จ',
    build: () {
      final repository = _PaymentRepositoryFake()
        ..checkout = PaymentCheckout(
          rentalId: 21,
          paymentOrderId: 'payment-1',
          checkoutUrl: Uri.parse('https://checkout.stripe.com/test'),
          status: 'checkout_pending',
        );
      return _cubit(repository);
    },
    act: (cubit) => cubit.start(_draft),
    expect: () => [
      const PaymentState(flowStatus: PaymentFlowStatus.creatingCheckout),
      PaymentState(
        flowStatus: PaymentFlowStatus.awaitingPayment,
        rentalId: 21,
        checkoutUrl: Uri.parse('https://checkout.stripe.com/test'),
        providerStatus: 'checkout_pending',
      ),
    ],
  );

  blocTest<PaymentCubit, PaymentState>(
    'แสดงสำเร็จเมื่อ backend ยืนยันสถานะ paid เท่านั้น',
    build: () {
      final repository = _PaymentRepositoryFake()
        ..paymentStatus = const RentalPaymentStatus(
          rentalId: 21,
          paymentOrderId: 'payment-1',
          status: 'paid',
          amountSatang: 150000,
          currency: 'thb',
        );
      return _cubit(repository);
    },
    act: (cubit) => cubit.refresh(rentalId: 21),
    expect: () => [
      const PaymentState(
        flowStatus: PaymentFlowStatus.checkingStatus,
        rentalId: 21,
      ),
      const PaymentState(
        flowStatus: PaymentFlowStatus.paid,
        rentalId: 21,
        providerStatus: 'paid',
      ),
    ],
  );

  blocTest<PaymentCubit, PaymentState>(
    'ไม่แสดงสำเร็จเมื่อ webhook ยังไม่ยืนยัน',
    build: () {
      final repository = _PaymentRepositoryFake()
        ..paymentStatus = const RentalPaymentStatus(
          rentalId: 21,
          paymentOrderId: 'payment-1',
          status: 'checkout_pending',
          amountSatang: 150000,
          currency: 'thb',
        );
      return _cubit(repository);
    },
    act: (cubit) => cubit.refresh(rentalId: 21),
    verify: (cubit) {
      expect(cubit.state.flowStatus, PaymentFlowStatus.awaitingPayment);
      expect(cubit.state.flowStatus, isNot(PaymentFlowStatus.paid));
    },
  );
}
