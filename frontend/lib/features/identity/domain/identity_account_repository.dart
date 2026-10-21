import 'dart:typed_data';
import 'identity_repository.dart';

class IdentityAccountDetails {
  IdentityAccountDetails(Map<String, dynamic> data)
    : fields = Map<String, String>.fromEntries(
        (data['fields'] as Map? ?? {}).entries.map(
          (entry) =>
              MapEntry(entry.key.toString(), entry.value?.toString() ?? ''),
        ),
      ),
      status = IdentityStatus(
        Map<String, dynamic>.from(data['status'] as Map? ?? {}),
      ),
      hasIdentity = data['has_identity'] == true,
      selfieWithCard = data['selfie_with_card'] == true,
      evidence = {
        for (final item in data['evidence'] as List? ?? [])
          item['kind'] as String: item['id'] as String,
      };
  final Map<String, String> fields, evidence;
  final IdentityStatus status;
  final bool hasIdentity, selfieWithCard;
  bool get pending =>
      status.request['status'] == 'pending' &&
      (DateTime.tryParse(
            status.request['deadline']?.toString() ?? '',
          )?.isAfter(DateTime.now()) ??
          true);
}

abstract interface class IdentityAccountRepository {
  Future<IdentityAccountDetails> accountDetails();
  Future<Uint8List> accountEvidence(String id);
  Future<void> updateAccount(
    Map<String, String> fields, {
    Uint8List? card,
    Uint8List? selfie,
  });
  void close();
}
