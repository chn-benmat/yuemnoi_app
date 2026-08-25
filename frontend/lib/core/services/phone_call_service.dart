import 'package:url_launcher/url_launcher.dart';

abstract interface class PhoneCallService {
  Future<bool> call(String phoneNumber);
}

String normalizePhoneNumberForDialer(String phoneNumber) {
  final compactPhone = phoneNumber.trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (!compactPhone.startsWith('+66')) return compactPhone;

  var localNumber = compactPhone.substring(3);
  if (localNumber.startsWith('0')) {
    localNumber = localNumber.substring(1);
  }
  return localNumber.isEmpty ? '' : '0$localNumber';
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
