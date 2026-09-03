import 'package:equatable/equatable.dart';

enum PaymentFlowStatus {
  initial,
  creatingCheckout,
  awaitingPayment,
  checkingStatus,
  paid,
  failed,
}

class PaymentState extends Equatable {
  const PaymentState({
    this.flowStatus = PaymentFlowStatus.initial,
    this.rentalId,
    this.checkoutUrl,
    this.providerStatus,
    this.errorMessage,
  });

  final PaymentFlowStatus flowStatus;
  final int? rentalId;
  final Uri? checkoutUrl;
  final String? providerStatus;
  final String? errorMessage;

  PaymentState copyWith({
    PaymentFlowStatus? flowStatus,
    int? rentalId,
    Uri? checkoutUrl,
    String? providerStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PaymentState(
      flowStatus: flowStatus ?? this.flowStatus,
      rentalId: rentalId ?? this.rentalId,
      checkoutUrl: checkoutUrl ?? this.checkoutUrl,
      providerStatus: providerStatus ?? this.providerStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    flowStatus,
    rentalId,
    checkoutUrl,
    providerStatus,
    errorMessage,
  ];
}
