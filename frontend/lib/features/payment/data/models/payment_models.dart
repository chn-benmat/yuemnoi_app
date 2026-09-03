import '../../domain/entities/payment.dart';

abstract final class PaymentModels {
  static PaymentCheckout checkoutFromJson(Map<String, dynamic> json) {
    final rentalId = _int(json['rental_id']);
    final paymentOrderId = _string(json['payment_order_id']);
    final checkoutUrl = Uri.tryParse(_string(json['checkout_url']));
    final status = _string(json['status']);
    if (rentalId == null ||
        rentalId <= 0 ||
        paymentOrderId.isEmpty ||
        checkoutUrl == null ||
        !checkoutUrl.hasScheme ||
        status.isEmpty) {
      throw const FormatException('Invalid payment checkout response');
    }
    return PaymentCheckout(
      rentalId: rentalId,
      paymentOrderId: paymentOrderId,
      checkoutUrl: checkoutUrl,
      status: status,
    );
  }

  static RentalPaymentStatus statusFromJson(Map<String, dynamic> json) {
    final rentalId = _int(json['rental_id']);
    final paymentOrderId = _string(json['payment_order_id']);
    final status = _string(json['status']);
    final amountSatang = _int(json['amount_satang']);
    final currency = _string(json['currency']);
    final paidAtValue = _string(json['paid_at']);
    if (rentalId == null ||
        rentalId <= 0 ||
        paymentOrderId.isEmpty ||
        status.isEmpty ||
        amountSatang == null ||
        amountSatang <= 0 ||
        currency.isEmpty) {
      throw const FormatException('Invalid payment status response');
    }
    return RentalPaymentStatus(
      rentalId: rentalId,
      paymentOrderId: paymentOrderId,
      status: status,
      amountSatang: amountSatang,
      currency: currency,
      paidAt: paidAtValue.isEmpty ? null : DateTime.tryParse(paidAtValue),
    );
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  static String _string(Object? value) =>
      value is String ? value.trim() : value?.toString().trim() ?? '';
}
