import 'dart:typed_data';

const identityCardRetentionConsentVersion = 'identity-v2';

bool identityValidBirthDate(String value, {DateTime? today}) {
  final birth = DateTime.tryParse(value);
  final now = (today ?? DateTime.now()).toUtc();
  final date = DateTime.utc(now.year, now.month, now.day);
  final birthday = birth == null
      ? null
      : DateTime.utc(birth.year, birth.month, birth.day);
  if (birth == null ||
      birth.year < 1 ||
      value !=
          '${birth.year.toString().padLeft(4, '0')}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}' ||
      birthday!.isAfter(date)) {
    return false;
  }
  return true;
}

class IdentityFailure implements Exception {
  const IdentityFailure(this.message);
  final String message;
}

class IdentityStatus {
  const IdentityStatus(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get request =>
      Map<String, dynamic>.from(data['request'] as Map? ?? {});
  Map<String, dynamic> get profile =>
      Map<String, dynamic>.from(data['profile'] as Map? ?? {});
  bool get canList => data['can_list'] == true;
  bool get enforcement => data['enforcement'] == true;
  bool get restricted {
    final control = data['control'] as Map?;
    return control?['suspended'] == true;
  }

  // ผลอนุมัติของเจ้าหน้าที่ไม่ผูกกับวันหมดอายุบัตร
  bool get verified => profile['status'] == 'approved';
}

abstract interface class IdentityRepository {
  Future<IdentityStatus> status();
  Future<Map<String, dynamic>> begin(String birthDate);
  Future<void> submit(
    String session,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  );
  void close();
}
