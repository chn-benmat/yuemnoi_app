import 'dart:typed_data';

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
  bool get pilot => data['pilot'] == true;
  // รองรับ backend รุ่นเดิมที่ยังส่งเฉพาะสิทธิ์กลุ่มทดลอง
  bool get available =>
      data['available'] is bool ? data['available'] == true : pilot;
  bool get canList => data['can_list'] == true;
  bool get enforcement => data['enforcement'] == true;
  bool get restricted {
    final control = data['control'] as Map?;
    return control?['suspended'] == true || control?['is_minor'] == true;
  }

  bool get guardianReady => data['guardian_id'] != null;
  bool get verified {
    if (profile['status'] != 'approved') return false;
    if (profile['lifetime'] == true) return true;
    final expiry = DateTime.tryParse(profile['expires_on']?.toString() ?? '');
    final today = DateTime.now();
    return expiry != null &&
        !expiry.isBefore(DateTime(today.year, today.month, today.day));
  }
}

abstract interface class IdentityRepository {
  Future<IdentityStatus> status();
  Future<Map<String, dynamic>> begin(bool minor);
  Future<Map<String, String>> readCard(String session, Uint8List card);
  Future<void> submit(
    String session,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  );
  Future<void> guardian(String child, String relationship, Uint8List authority);
  void close();
}
