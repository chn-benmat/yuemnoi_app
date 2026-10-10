import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/presentation/identity_cubit.dart';

class Repository implements IdentityRepository {
  @override
  Future<Map<String, String>> readCard(String session, Uint8List card) async =>
      {};
  DateTime until = DateTime.now().add(const Duration(minutes: 15));
  bool failBegin = false;
  bool failSubmit = false, failStatusAfterSubmit = false;
  int submitted = 0;
  Map<String, dynamic>? request;
  @override
  Future<IdentityStatus> status() async {
    if (submitted > 0 && failStatusAfterSubmit) {
      throw const IdentityFailure('status unavailable');
    }
    return IdentityStatus({
      'pilot': true,
      'request': submitted > 0 ? {'status': 'pending'} : request,
    });
  }

  @override
  Future<Map<String, dynamic>> begin(bool minor) async {
    if (failBegin) throw const IdentityFailure('guardian_consent_required');
    return {
      'id': 'synthetic-session',
      'capture_until': until.toUtc().toIso8601String(),
    };
  }

  @override
  Future<void> submit(
    String id,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  ) async {
    if (failSubmit) throw const IdentityFailure('upload unavailable');
    submitted++;
  }

  @override
  Future<void> guardian(String c, String r, Uint8List image) async {}
  @override
  void close() {}
}

void main() {
  test('ส่งล้มเหลวรักษารอบเดิมไว้ให้ลองใหม่', () async {
    final repository = Repository()..failSubmit = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin(false);
    final until = cubit.state.captureUntil;
    expect(await cubit.submit({}, Uint8List(1), Uint8List(1)), isFalse);
    expect(cubit.state.session, 'synthetic-session');
    expect(cubit.state.captureUntil, until);
    expect(cubit.state.busy, isFalse);
    await cubit.close();
  });
  test('ส่งสำเร็จแต่โหลดสถานะพังไม่กลับไปให้ส่งซ้ำ', () async {
    final repository = Repository()..failStatusAfterSubmit = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin(false);
    expect(await cubit.submit({}, Uint8List(1), Uint8List(1)), isTrue);
    expect(cubit.state.status!.request['status'], 'pending');
    expect(cubit.state.session, isNull);
    await cubit.close();
  });
  test('บัญชีทั่วไปเริ่มยืนยันได้เมื่อเปิดใช้ทุกบัญชี', () {
    const status = IdentityStatus({'pilot': false, 'available': true});
    expect(status.pilot, isFalse);
    expect(status.available, isTrue);
    expect(status.verified, isFalse);
  });
  test('สถานะปิดใช้ไม่ถูกสิทธิ์ทดลองจากข้อมูลเดิมเปิดข้าม', () {
    expect(
      const IdentityStatus({'pilot': true, 'available': false}).available,
      isFalse,
    );
    expect(const IdentityStatus({}).available, isFalse);
    expect(const IdentityStatus({'pilot': true}).available, isTrue);
  });
  test('กลับเข้าหน้าจอแล้วถ่ายต่อในรอบที่ยังไม่หมดอายุ', () async {
    final repository = Repository();
    repository.request = {
      'id': 'existing-session',
      'status': 'capture',
      'capture_until': repository.until.toUtc().toIso8601String(),
    };
    final cubit = IdentityCubit(repository);
    await cubit.load();
    expect(cubit.state.session, 'existing-session');
    expect(cubit.state.captureUntil, repository.until.toUtc());
    await cubit.close();
  });
  test('ไม่แสดงยืนยันเมื่อไม่มีผลหรือบัตรหมดอายุ', () {
    expect(const IdentityStatus({}).verified, isFalse);
    expect(
      const IdentityStatus({
        'profile': {'status': 'approved', 'expires_on': '2000-01-01'},
      }).verified,
      isFalse,
    );
    expect(
      const IdentityStatus({
        'profile': {'status': 'approved', 'lifetime': true},
      }).verified,
      isTrue,
    );
  });
  test('ความยินยอมผู้ปกครองล้มเหลวไม่เปิดรอบถ่ายภาพ', () async {
    final repository = Repository()..failBegin = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin(true);
    expect(cubit.state.session, isNull);
    expect(cubit.state.error, 'guardian_consent_required');
    await cubit.close();
  });
  test('รอบหมดอายุไม่ส่งหลักฐาน', () async {
    final repository = Repository()
      ..until = DateTime.now().subtract(const Duration(seconds: 1));
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin(false);
    expect(await cubit.submit({}, Uint8List(1), Uint8List(1)), isFalse);
    expect(repository.submitted, 0);
    await cubit.close();
  });
  test('ส่งแล้วรอคนตรวจ ไม่มีการอนุมัติจากแอป', () async {
    final repository = Repository();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin(false);
    expect(await cubit.submit({}, Uint8List(1), Uint8List(1)), isTrue);
    expect(cubit.state.status!.request['status'], 'pending');
    expect(cubit.state.status!.verified, isFalse);
    expect(cubit.state.session, isNull);
    await cubit.close();
  });
}
