import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/widgets/app_primary_button.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/identity/domain/identity_account_repository.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/domain/thai_address.dart';
import 'package:frontend/features/identity/presentation/identity_account_cubit.dart';
import 'package:frontend/features/identity/presentation/pages/identity_account_page.dart';

class AccountRepository implements IdentityAccountRepository {
  bool pending = false, fail = false, selfieWithCard = true;
  int sends = 0;
  Completer<void>? loadGate;
  final fields = <String, String>{
    'name_prefix': 'นาย',
    'first_name': 'ทดสอบ',
    'last_name': 'ระบบ',
    'citizen_id': '1234567890123',
    'birth_date': '2000-02-29',
    'address_detail': '99 ถนนทดสอบ',
    'province': 'กรุงเทพมหานคร',
    'district': 'เขตพระนคร',
    'subdistrict': 'พระบรมมหาราชวัง',
    'postal_code': '10200',
  };
  @override
  Future<IdentityAccountDetails> accountDetails() async {
    await loadGate?.future;
    return IdentityAccountDetails({
      'fields': fields,
      'has_identity': true,
      'selfie_with_card': selfieWithCard,
      'evidence': [
        {'kind': 'card', 'id': 'card'},
        {'kind': 'selfie', 'id': 'selfie'},
      ],
      'status': {
        'profile': {'status': 'approved'},
        'request': {'status': pending ? 'pending' : 'approved'},
      },
    });
  }

  @override
  Future<Uint8List> accountEvidence(String id) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  @override
  Future<void> updateAccount(
    Map<String, String> fields, {
    Uint8List? card,
    Uint8List? selfie,
  }) async {
    sends++;
    if (fail) throw const IdentityFailure('เครือข่ายขัดข้อง');
    this.fields.addAll(fields);
    pending = true;
  }

  @override
  void close() {}
}

class Addresses implements ThaiAddressRepository {
  @override
  Future<List<ThaiProvince>> load() async => const [
    ThaiProvince(
      id: 1,
      name: 'กรุงเทพมหานคร',
      districts: [
        ThaiDistrict(
          id: 1,
          name: 'เขตพระนคร',
          subdistricts: [
            ThaiSubdistrict(
              id: 1,
              name: 'พระบรมมหาราชวัง',
              postalCodes: ['10200'],
            ),
          ],
        ),
      ],
    ),
  ];
}

Future<IdentityAccountCubit> open(
  WidgetTester tester,
  AccountRepository repo,
) async {
  final cubit = IdentityAccountCubit(repo);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BlocProvider.value(
                  value: cubit,
                  child: IdentityAccountPage(addressRepository: Addresses()),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await cubit.load();
  await tester.pumpAndSettle();
  addTearDown(cubit.close);
  return cubit;
}

void main() {
  testWidgets('โหลดด้วย skeleton เฉพาะเนื้อหา ปุ่มกับ navbar คงเดิม', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = AccountRepository()..loadGate = gate;
    final cubit = IdentityAccountCubit(repo)..load();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: BlocProvider.value(
          value: cubit,
          child: IdentityAccountPage(addressRepository: Addresses()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(SkeletonShimmer), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(AppBar),
        matching: find.byType(SkeletonShimmer),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(AppPrimaryButton),
        matching: find.byType(SkeletonShimmer),
      ),
      findsNothing,
    );
    expect(
      tester.widget<AppPrimaryButton>(find.byType(AppPrimaryButton)).isLoading,
      isFalse,
    );
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    final buttonRect = tester.getRect(find.byType(AppPrimaryButton));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShimmer), findsNothing);
    expect(tester.getRect(find.byType(AppPrimaryButton)), buttonRect);
  });
  testWidgets('การ์ดรูปเรียงเต็มความกว้างและคำแนะนำเลขบัตรอยู่เหนือช่องกรอก', (
    tester,
  ) async {
    await open(tester, AccountRepository());
    expect(find.text('01'), findsNothing);
    expect(find.text('02'), findsNothing);
    expect(find.text('03'), findsNothing);
    expect(
      tester.getTopLeft(find.text('รูปบัตรประชาชน')).dy,
      greaterThan(tester.getTopLeft(find.text('รูปคู่บัตรประชาชน')).dy),
    );
    expect(find.byTooltip('นำรูปคู่บัตรออก'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('citizen_id')));
    final label = tester.getTopLeft(find.text('เลขบัตรประชาชน')).dy;
    final hint = tester
        .getTopLeft(find.text('เปลี่ยนเลขบัตร กรุณาติดต่อเจ้าหน้าที่'))
        .dy;
    final field = tester
        .getTopLeft(find.byKey(const ValueKey('citizen_id')))
        .dy;
    expect(hint, greaterThan(label));
    expect(hint, lessThan(field));
  });
  testWidgets('นำรูปออกจากแบบร่างแล้วต้องเพิ่มรูปให้ครบก่อนส่ง', (
    tester,
  ) async {
    final repo = AccountRepository();
    await open(tester, repo);
    await tester.ensureVisible(find.byTooltip('นำรูปคู่บัตรออก'));
    await tester.tap(find.byTooltip('นำรูปคู่บัตรออก'));
    await tester.pump();
    await tester.tap(find.text('บันทึกข้อมูล'));
    await tester.pumpAndSettle();
    expect(
      find.text('กรุณาเพิ่มรูปบัตรและรูปคู่บัตรประชาชนให้ครบ'),
      findsOneWidget,
    );
    expect(repo.sends, 0);
  });
  testWidgets(
    'มีรูปเดิมครบแม้ไม่มี metadata รุ่นใหม่ ต้องบันทึกได้โดยไม่ขอถ่ายซ้ำ',
    (tester) async {
      final repo = AccountRepository()..selfieWithCard = false;
      await open(tester, repo);
      expect(find.text('กรุณาเพิ่มรูปถือบัตรประชาชนก่อนส่งคำขอ'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
      await tester.enterText(
        find.byKey(const ValueKey('first_name')),
        'ชื่อใหม่',
      );
      await tester.pump();
      await tester.tap(find.text('บันทึกข้อมูล'));
      await tester.pumpAndSettle();
      expect(find.text('ส่งข้อมูลให้เจ้าหน้าที่ตรวจสอบ?'), findsOneWidget);
      await tester.tap(find.text('ยืนยันส่งข้อมูล'));
      await tester.pumpAndSettle();
      expect(repo.sends, 1);
    },
  );
  testWidgets('เลขบัตรอ่านอย่างเดียว และถามก่อนทิ้งข้อมูลที่แก้ไข', (
    tester,
  ) async {
    await open(tester, AccountRepository());
    await tester.ensureVisible(find.byKey(const ValueKey('citizen_id')));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('citizen_id')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
    await tester.enterText(
      find.byKey(const ValueKey('first_name')),
      'ชื่อใหม่',
    );
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('ออกโดยไม่บันทึกการแก้ไข?'), findsOneWidget);
    await tester.tap(find.text('แก้ไขต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อใหม่'), findsOneWidget);
  });
  testWidgets('ออกได้ทันทีเมื่อยังไม่แก้ไข', (tester) async {
    await open(tester, AccountRepository());
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('ยืนยันก่อนส่ง ใช้รูปเดิม และล็อกฟอร์มเมื่อส่งสำเร็จ', (
    tester,
  ) async {
    final repo = AccountRepository();
    await open(tester, repo);
    await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
    await tester.enterText(
      find.byKey(const ValueKey('first_name')),
      'ชื่อใหม่',
    );
    await tester.pump();
    await tester.tap(find.text('บันทึกข้อมูล'));
    await tester.pumpAndSettle();
    expect(repo.sends, 0);
    expect(find.text('ส่งข้อมูลให้เจ้าหน้าที่ตรวจสอบ?'), findsOneWidget);
    await tester.tap(find.text('ยืนยันส่งข้อมูล'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(find.text('ส่งข้อมูลแล้ว'), findsOneWidget);
    await tester.tap(find.text('เข้าใจแล้ว'));
    await tester.pumpAndSettle();
    expect(find.text('รอตรวจสอบ'), findsWidgets);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('first_name')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
  });
  testWidgets('ส่งไม่สำเร็จยังเก็บข้อความไว้แก้และส่งใหม่', (tester) async {
    final repo = AccountRepository()..fail = true;
    await open(tester, repo);
    await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
    await tester.enterText(
      find.byKey(const ValueKey('first_name')),
      'ชื่อใหม่',
    );
    await tester.pump();
    await tester.tap(find.text('บันทึกข้อมูล'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันส่งข้อมูล'));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อใหม่'), findsOneWidget);
    expect(find.text('เครือข่ายขัดข้อง'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('first_name')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isFalse,
    );
  });
  testWidgets('หน้าจอแคบและตัวอักษรใหญ่ไม่ล้น', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, AccountRepository());
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
