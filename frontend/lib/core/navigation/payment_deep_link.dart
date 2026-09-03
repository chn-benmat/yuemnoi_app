abstract final class PaymentDeepLink {
  static int? parseRentalId(Uri uri) {
    final isCustomLink =
        uri.scheme == 'yuemnoi' &&
        uri.host == 'payments' &&
        uri.path == '/return';
    final isWebLink =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path == '/payments/return';
    if (!isCustomLink && !isWebLink) return null;

    final type = uri.queryParameters['type'];
    if (type == 'wallet' || type == 'topup') return null;

    final rentalId = int.tryParse(uri.queryParameters['rental_id'] ?? '');
    return rentalId != null && rentalId > 0 ? rentalId : null;
  }

  static bool isWalletReturn(Uri uri) {
    final isCustomLink =
        uri.scheme == 'yuemnoi' &&
        (uri.host == 'wallet' || (uri.host == 'payments' && uri.path == '/return'));
    final isWebLink =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.path == '/wallet/return' || uri.path == '/payments/return');
    if (!isCustomLink && !isWebLink) return false;

    final type = uri.queryParameters['type'];
    return type == 'wallet' || type == 'topup' || uri.host == 'wallet' || uri.path == '/wallet/return';
  }

  static String? parseResult(Uri uri) {
    return uri.queryParameters['result'];
  }
}
