import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/presentation/identity_cubit.dart';
import 'package:frontend/features/identity/presentation/identity_page.dart';

class RolloutRepository implements IdentityRepository {
  RolloutRepository({Map<String, dynamic>? data})
    : data = data ?? {'available': true};
  Map<String, dynamic> data;
  int begins = 0, reads = 0, submits = 0;
  bool failSubmit = false, failRead = false;
  @override
  Future<IdentityStatus> status() async => IdentityStatus(data);
  @override
  Future<Map<String, dynamic>> begin(bool minor) async {
    begins++;
    final session = {
      'id': 'test-session',
      'capture_until': DateTime.now()
          .add(const Duration(minutes: 15))
          .toUtc()
          .toIso8601String(),
    };
    data = {
      ...data,
      'request': {...session, 'status': 'capture'},
    };
    return session;
  }

  @override
  Future<Map<String, String>> readCard(String session, Uint8List card) async {
    reads++;
    if (failRead) throw const IdentityFailure('OCR unavailable');
    return {
      'legal_name': 'ทดสอบ ระบบ',
      'citizen_id': '0000000000001',
      'birth_date': '2000-01-01',
      'expires_on': '2035-01-01',
    };
  }

  @override
  Future<void> submit(
    String session,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  ) async {
    submits++;
    if (failSubmit) throw const IdentityFailure('ส่งไม่สำเร็จ ข้อมูลยังอยู่');
    data = {
      ...data,
      'request': {'id': session, 'status': 'pending'},
    };
  }

  @override
  Future<void> guardian(
    String child,
    String relationship,
    Uint8List authority,
  ) async {}
  @override
  void close() {}
}

Future<RolloutRepository> showPage(
  WidgetTester tester, {
  RolloutRepository? repository,
  double scale = 1,
}) async {
  final repo = repository ?? RolloutRepository();
  final cubit = IdentityCubit(repo);
  addTearDown(cubit.close);
  await cubit.load();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: BlocProvider.value(
        value: cubit,
        child: IdentityPage(
          capture: (context, kind) async => base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1sAAAAASUVORK5CYII=',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> selectAge(WidgetTester tester, String age) async {
  await tester.ensureVisible(find.byType(DropdownButtonFormField<bool>));
  await tester.tap(find.byType(DropdownButtonFormField<bool>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(age).last);
  await tester.pumpAndSettle();
}

Future<void> begin(WidgetTester tester) async {
  await selectAge(tester, 'อายุ 20 ปีขึ้นไป');
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tapText(tester, 'ยินยอมและเริ่มยืนยัน');
}

Future<void> photos(WidgetTester tester) async {
  await tapText(tester, 'ถ่ายบัตรประชาชน');
  await tapText(tester, 'ถัดไป: ถ่ายใบหน้า');
  await tapText(tester, 'ถ่ายใบหน้า');
  await tapText(tester, 'ถัดไป: ตรวจข้อมูล');
}

void main() {
  testWidgets('ตัวเลือกวันที่ปรับวันให้ตรงเดือนและปีที่เลือก', (tester) async {
    await showPage(tester);
    await begin(tester);
    await photos(tester);
    await tester.ensureVisible(find.byType(OutlinedButton).first);
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).at(0),
        )
        .onChanged!(31);
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).at(1),
        )
        .onChanged!(2);
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).at(2),
        )
        .onChanged!(2001);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>).first,
          )
          .initialValue,
      28,
    );
    await tapText(tester, 'ใช้วันที่นี้');
    expect(find.textContaining('2544'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('บัญชีทั่วไปเริ่มได้เมื่อเลือกอายุและยินยอมเท่านั้น', (
    tester,
  ) async {
    final repo = await showPage(tester);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'ยินยอมและเริ่มยืนยัน'),
    );
    expect(button.onPressed, isNull);
    await begin(tester);
    expect(repo.begins, 1);
    expect(find.text('เริ่มจากบัตรประชาชน'), findsOneWidget);
    expect(find.textContaining('ขั้นตอน 1 / 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('ผู้เยาว์ไม่มีผู้ปกครองยังไม่เริ่มเก็บภาพ', (tester) async {
    final repo = await showPage(tester);
    await selectAge(tester, 'อายุต่ำกว่า 20 ปี');
    expect(
      find.textContaining('ระหว่างนี้ยังไม่เก็บภาพของคุณ'),
      findsOneWidget,
    );
    expect(find.text('คัดลอกรหัสให้ผู้ปกครอง'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'ยินยอมและเริ่มยืนยัน'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.begins, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('ปิด public availability ยังจำกัดบัญชีทั่วไป', (tester) async {
    await showPage(
      tester,
      repository: RolloutRepository(data: {'available': false}),
    );
    expect(find.text('ยังเปิดยืนยันไม่ได้'), findsOneWidget);
    expect(find.text('ยินยอมและเริ่มยืนยัน'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'OCR เติมแบบฟอร์ม ย้อนกลับและ refresh ไม่ล้าง แล้วส่งเข้ารอตรวจ',
    (tester) async {
      final repo = await showPage(tester);
      await begin(tester);
      await photos(tester);
      expect(repo.reads, 1);
      expect(find.text('ทดสอบ ระบบ'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'แก้ไข ชื่อ');
      await tapText(tester, 'ตรวจสรุปก่อนส่ง');
      expect(find.text('แก้ไข ชื่อ'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'ส่งคำขอยืนยันตัวตน'),
            )
            .onPressed,
        isNull,
      );
      await tapText(tester, 'แก้ไขข้อมูล');
      expect(find.text('แก้ไข ชื่อ'), findsOneWidget);
      await tester.tap(find.byTooltip('โหลดสถานะใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('แก้ไข ชื่อ'), findsOneWidget);
      expect(find.text('ตรวจข้อมูลให้ตรงบัตร'), findsOneWidget);
      expect(repo.submits, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('ส่งล้มเหลวยังเก็บรูปและชื่อที่กรอกเพื่อส่งซ้ำ', (tester) async {
    final repo = RolloutRepository()..failSubmit = true;
    await showPage(tester, repository: repo);
    await begin(tester);
    await photos(tester);
    await tapText(tester, 'ตรวจสรุปก่อนส่ง');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 1);
    expect(find.text('ทดสอบ ระบบ'), findsOneWidget);
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    repo.failSubmit = false;
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 2);
    expect(find.text('รับคำขอของคุณแล้ว'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('OCR ล้มเหลวกรอกเองได้และแสดง validation ชัดเจน', (tester) async {
    await showPage(tester, repository: RolloutRepository()..failRead = true);
    await begin(tester);
    await photos(tester);
    await tapText(tester, 'ตรวจสรุปก่อนส่ง');
    expect(find.text('กรุณากรอกข้อมูลช่องนี้'), findsOneWidget);
    expect(find.text('กรอกเลขบัตร 13 หลักให้ครบ'), findsOneWidget);
    expect(find.text('กรุณาเลือกวันที่'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
  for (final kind in [
    'pending',
    'corrections',
    'rejected',
    'expired',
    'approved',
  ]) {
    testWidgets('หน้าสถานะ $kind มีคำสั่งถัดไป', (tester) async {
      await showPage(
        tester,
        repository: RolloutRepository(
          data: {
            'available': true,
            'can_list': kind == 'approved',
            'request': {'status': kind, 'reason': 'คำแนะนำทดสอบ'},
            if (kind == 'approved')
              'profile': {'status': 'approved', 'lifetime': true},
          },
        ),
      );
      final expected = {
        'pending': 'รับคำขอของคุณแล้ว',
        'corrections': 'แก้อีกนิด แล้วส่งใหม่',
        'rejected': 'คำขอยังไม่ผ่าน',
        'expired': 'เริ่มยืนยันตัวตนใหม่',
        'approved': 'ยืนยันตัวตนแล้ว',
      };
      expect(find.text(expected[kind]!), findsOneWidget);
      expect(find.text('ถ่ายบัตรประชาชน'), findsNothing);
      if (kind == 'approved') {
        await tapText(tester, 'ดูแลบัญชีผู้เยาว์');
        expect(find.text('รหัสบัญชีผู้เยาว์'), findsOneWidget);
        expect(find.byTooltip('วางรหัสบัญชี'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('ขนาดหน้าจอ $width และตัวอักษรขยายไม่ล้น', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showPage(tester, scale: 1.3);
      expect(tester.takeException(), isNull);
      await begin(tester);
      await photos(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
