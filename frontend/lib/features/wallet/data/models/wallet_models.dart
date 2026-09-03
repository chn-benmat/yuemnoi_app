import '../../domain/entities/wallet_info.dart';
import '../../domain/entities/wallet_top_up_checkout.dart';
import '../../domain/entities/wallet_transaction.dart';

abstract final class WalletModels {
  static WalletInfo infoFromJson(Map<String, dynamic> json) {
    final balanceRaw = json['balance'] ?? json['balance_satang'] ?? json['total_balance'];
    double balance = 0.0;
    if (balanceRaw is num) {
      // If balance is in satang (integer > 100 with no decimal in field name like balance_satang)
      if (json.containsKey('balance_satang')) {
        balance = balanceRaw.toDouble() / 100.0;
      } else {
        balance = balanceRaw.toDouble();
      }
    } else if (balanceRaw is String) {
      balance = double.tryParse(balanceRaw) ?? 0.0;
    }

    final currency = (json['currency'] as String? ?? 'THB').toUpperCase();
    final rawTransactions = json['transactions'] as List<dynamic>? ?? const [];
    final transactions = rawTransactions
        .whereType<Map<String, dynamic>>()
        .map(transactionFromJson)
        .toList();

    return WalletInfo(
      balance: balance,
      currency: currency,
      transactions: transactions,
    );
  }

  static WalletTransaction transactionFromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['transaction_id'] ?? '').toString();
    final title = (json['title'] ?? json['description'] ?? 'เติมเงินเข้าบัญชี').toString();
    
    final amountRaw = json['amount'] ?? json['amount_satang'];
    double amount = 0.0;
    if (amountRaw is num) {
      if (json.containsKey('amount_satang')) {
        amount = amountRaw.toDouble() / 100.0;
      } else {
        amount = amountRaw.toDouble();
      }
    } else if (amountRaw is String) {
      amount = double.tryParse(amountRaw) ?? 0.0;
    }

    final dateStr = json['created_at'] ?? json['date_time'] ?? json['timestamp'];
    final dateTime = dateStr != null
        ? DateTime.tryParse(dateStr.toString())?.toLocal() ?? DateTime.now()
        : DateTime.now();

    final type = (json['type'] ?? 'top_up').toString();
    final status = (json['status'] ?? 'เสร็จสิ้น').toString();

    return WalletTransaction(
      id: id,
      title: title,
      amount: amount,
      dateTime: dateTime,
      type: type,
      status: status,
    );
  }

  static WalletTopUpCheckout topUpCheckoutFromJson(Map<String, dynamic> json) {
    final sessionId = (json['session_id'] ?? json['checkout_session_id'] ?? '').toString();
    final urlStr = (json['checkout_url'] ?? json['url'] ?? '').toString();
    final uri = Uri.tryParse(urlStr);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Invalid Stripe checkout URL returned');
    }

    final amountRaw = json['amount'] ?? json['amount_satang'];
    double amount = 0.0;
    if (amountRaw is num) {
      amount = json.containsKey('amount_satang')
          ? amountRaw.toDouble() / 100.0
          : amountRaw.toDouble();
    }

    return WalletTopUpCheckout(
      sessionId: sessionId,
      checkoutUrl: uri,
      amount: amount,
    );
  }
}
