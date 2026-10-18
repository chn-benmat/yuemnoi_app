import 'package:url_launcher/url_launcher.dart';

import '../utils/phone_formatter.dart';

abstract interface class PhoneCallService {
  Future<bool> call(String phoneNumber);
}

String normalizePhoneNumberForDialer(String phoneNumber) {
  return PhoneFormatter.formatForDialer(phoneNumber);
}

class UrlPhoneCallService implements PhoneCallService {
  const UrlPhoneCallService();

  @override
  Future<bool> call(String phoneNumber) {
    final normalizedPhone = normalizePhoneNumberForDialer(phoneNumber);
    if (normalizedPhone.isEmpty) return Future.value(false);

    return launchUrl(
      Uri(scheme: 'tel', path: normalizedPhone),
      mode: LaunchMode.externalApplication,
    );
  }
}
