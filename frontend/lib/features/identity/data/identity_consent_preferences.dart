import 'package:shared_preferences/shared_preferences.dart';

import '../domain/identity_account_repository.dart';
import '../domain/identity_repository.dart';

class IdentityConsentPreferences implements IdentityConsentStore {
  IdentityConsentPreferences(String? userId)
    : _key = userId == null || userId.isEmpty
          ? null
          : 'identity_consent.$identityCardRetentionConsentVersion.$userId';

  final String? _key;

  @override
  Future<bool> hasAccepted() async {
    final key = _key;
    if (key == null) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) == true;
  }

  @override
  Future<bool> saveAcceptance() async {
    final key = _key;
    if (key == null) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.setBool(key, true);
  }
}
