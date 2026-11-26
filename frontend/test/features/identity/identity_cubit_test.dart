import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/presentation/identity_cubit.dart';

class Repository implements IdentityRepository {
  DateTime until = DateTime.now().add(const Duration(minutes: 15));
  bool failBegin = false;
  bool failSubmit = false, failStatusAfterSubmit = false;
  int submitted = 0, begins = 0;
  String? beganWithBirthDate;
  bool? returnedMinor;
  Completer<Map<String, dynamic>>? starting;
  Completer<IdentityStatus>? refresh;
  Map<String, dynamic>? request;
  @override
  Future<IdentityStatus> status() async {
    if (submitted > 0 && refresh != null) return refresh!.future;
    if (submitted > 0 && failStatusAfterSubmit) {
      throw const IdentityFailure('status unavailable');
    }
    return IdentityStatus({
      'request': submitted > 0 ? {'status': 'pending'} : request,
    });
  }

  @override
  Future<Map<String, dynamic>> begin(String birthDate) async {
    begins++;
    beganWithBirthDate = birthDate;
    if (failBegin) throw const IdentityFailure('begin unavailable');
    if (starting != null) return starting!.future;
    return {
      'id': 'synthetic-session',
      'capture_until': until.toUtc().toIso8601String(),
      if (returnedMinor != null) 'is_minor': returnedMinor,
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
  void close() {}
}

void main() {
  test('รับวันเกิดทุกวัยและปฏิเสธวันที่ผิดหรืออนาคต', () {
    final today = DateTime.utc(2026, 10, 11);
    for (final value in [
      '2006-10-11',
      '2013-10-11',
      '2021-01-01',
      '2026-10-11',
      '1890-01-01',
    ]) {
      expect(
        identityValidBirthDate(value, today: today),
        isTrue,
        reason: value,
      );
    }
    for (final value in ['', '2000-02-30', '2026-10-12']) {
      expect(
        identityValidBirthDate(value, today: today),
        isFalse,
        reason: value,
      );
    }
  });
  test('ข้อมูลผู้เยาว์เก่าไม่จำกัดสิทธิ์ แต่การระงับบัญชียังจำกัด', () {
    expect(
      const IdentityStatus({
        'control': {'is_minor': true},
      }).restricted,
      isFalse,
    );
    expect(
      const IdentityStatus({
        'control': {'is_minor': true, 'suspended': true},
      }).restricted,
      isTrue,
    );
  });

  test('วันเกิดไม่ถูกต้องไม่เรียกเริ่มรอบและไม่มี session', () async {
    final cubit = IdentityCubit(Repository());
    await cubit.load();
    await cubit.begin('2000-02-30');
    expect(cubit.state.session, isNull);
    expect(cubit.state.error, 'กรุณาตรวจวันเกิดให้ถูกต้อง');
    await cubit.close();
  });

  test('แสดงรับคำขอทันทีแม้โหลดสถานะล่าสุดยังไม่เสร็จ', () async {
    final repository = Repository()..refresh = Completer<IdentityStatus>();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    var completed = false;
    final submission = cubit
        .submit({'birth_date': '2000-01-01'}, Uint8List(1), Uint8List(1))
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    final returnedBeforeRefresh = completed;
    final pendingBeforeRefresh = cubit.state.status?.request['status'];
    final busyBeforeRefresh = cubit.state.busy;
    repository.refresh!.complete(
      const IdentityStatus({
        'request': {'status': 'pending'},
      }),
    );
    expect(await submission, isTrue);
    expect(returnedBeforeRefresh, isTrue);
    expect(pendingBeforeRefresh, 'pending');
    expect(busyBeforeRefresh, isFalse);
    await cubit.close();
  });
  test('สถานะที่กลับมาช้าไม่ทับรอบใหม่และไม่ส่งคำขอเดิมซ้ำ', () async {
    final repository = Repository()..refresh = Completer<IdentityStatus>();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isFalse,
    );
    await cubit.begin('2000-01-01');
    repository.refresh!.complete(
      const IdentityStatus({
        'request': {'status': 'pending'},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.session, 'synthetic-session');
    expect(cubit.state.sent, isFalse);
    expect(repository.submitted, 1);
    await cubit.close();
  });
  test('ปิดหน้าจอระหว่างโหลดสถานะไม่ emit หลังปิด', () async {
    final repository = Repository()..refresh = Completer<IdentityStatus>();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    await cubit.close();
    repository.refresh!.completeError(const IdentityFailure('cancelled'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.isClosed, isTrue);
  });
  test('ส่งล้มเหลวรักษารอบเดิมไว้ให้ลองใหม่', () async {
    final repository = Repository()..failSubmit = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    final until = cubit.state.captureUntil;
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isFalse,
    );
    expect(cubit.state.session, 'synthetic-session');
    expect(cubit.state.captureUntil, until);
    expect(cubit.state.busy, isFalse);
    await cubit.close();
  });
  test('ส่งสำเร็จแต่โหลดสถานะพังไม่กลับไปให้ส่งซ้ำ', () async {
    final repository = Repository()..failStatusAfterSubmit = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(cubit.state.status!.request['status'], 'pending');
    expect(cubit.state.session, isNull);
    await cubit.close();
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
  test('แสดงผลอนุมัติโดยไม่ตรวจวันหมดอายุบัตร', () {
    expect(const IdentityStatus({}).verified, isFalse);
    expect(
      const IdentityStatus({
        'profile': {'status': 'approved', 'expires_on': '2000-01-01'},
      }).verified,
      isTrue,
    );
    expect(
      const IdentityStatus({
        'profile': {'status': 'approved', 'lifetime': true},
      }).verified,
      isTrue,
    );
  });
  test('เริ่มคำขอไม่สำเร็จเมื่อกดส่งแล้วไม่อัปโหลดภาพ', () async {
    final repository = Repository()..failBegin = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    expect(
      await cubit.submit(
        {'birth_date': '${DateTime.now().year - 10}-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isFalse,
    );
    expect(cubit.state.session, isNull);
    expect(cubit.state.error, 'begin unavailable');
    expect(repository.begins, 1);
    expect(repository.submitted, 0);
    await cubit.close();
  });
  test('รอบหมดอายุไม่ส่งหลักฐาน', () async {
    final repository = Repository()
      ..until = DateTime.now().subtract(const Duration(seconds: 1));
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isFalse,
    );
    expect(repository.submitted, 0);
    await cubit.close();
  });
  test('ส่งแล้วรอคนตรวจ ไม่มีการอนุมัติจากแอป', () async {
    final repository = Repository();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(cubit.state.status!.request['status'], 'pending');
    expect(cubit.state.status!.verified, isFalse);
    expect(cubit.state.session, isNull);
    await cubit.close();
  });

  test('กดส่งครั้งเดียวเริ่มคำขอด้วยวันเกิดแล้วอัปโหลด', () async {
    final repository = Repository();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    expect(repository.begins, 0);
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(repository.begins, 1);
    expect(repository.beganWithBirthDate, '2000-01-01');
    expect(repository.submitted, 1);
    await cubit.close();
  });

  test('ไม่มีวันเกิดไม่เริ่มคำขอหรืออัปโหลด', () async {
    final repository = Repository();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    expect(await cubit.submit({}, Uint8List(1), Uint8List(1)), isFalse);
    expect(repository.begins, 0);
    expect(repository.submitted, 0);
    expect(cubit.state.error, 'กรุณาตรวจวันเกิดให้ถูกต้อง');
    await cubit.close();
  });

  test('รอบเดิมหมดอายุเริ่มใหม่ตอนส่งโดยใช้ภาพเดิมได้', () async {
    final repository = Repository()
      ..until = DateTime.now().subtract(const Duration(seconds: 1));
    final cubit = IdentityCubit(repository);
    await cubit.load();
    await cubit.begin('2000-01-01');
    repository.until = DateTime.now().add(const Duration(minutes: 15));
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(repository.begins, 2);
    expect(repository.submitted, 1);
    await cubit.close();
  });

  test('ระหว่างเริ่มคำขอกดส่งซ้ำไม่ได้และอัปโหลดครั้งเดียว', () async {
    final repository = Repository()
      ..starting = Completer<Map<String, dynamic>>();
    final cubit = IdentityCubit(repository);
    await cubit.load();
    final first = cubit.submit(
      {'birth_date': '2000-01-01'},
      Uint8List(1),
      Uint8List(1),
    );
    expect(cubit.state.busy, isTrue);
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isFalse,
    );
    expect(repository.begins, 1);
    expect(repository.submitted, 0);
    repository.starting!.complete({
      'id': 'synthetic-session',
      'capture_until': repository.until.toIso8601String(),
    });
    expect(await first, isTrue);
    expect(repository.submitted, 1);
    await cubit.close();
  });

  test('ช่วงอายุจากเซิร์ฟเวอร์รุ่นเดิมไม่ขัดขวางการส่งคำขอ', () async {
    final repository = Repository()..returnedMinor = true;
    final cubit = IdentityCubit(repository);
    await cubit.load();
    expect(
      await cubit.submit(
        {'birth_date': '2000-01-01'},
        Uint8List(1),
        Uint8List(1),
      ),
      isTrue,
    );
    expect(repository.submitted, 1);
    await cubit.close();
  });
}
