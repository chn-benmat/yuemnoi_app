import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/widgets/app_primary_button.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/identity/data/identity_consent_preferences.dart';
import 'package:frontend/features/identity/domain/identity_account_repository.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/domain/thai_address.dart';
import 'package:frontend/features/identity/presentation/identity_account_cubit.dart';
import 'package:frontend/features/identity/presentation/pages/identity_account_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountRepository implements IdentityAccountRepository {
  bool pending = false, fail = false, selfieWithCard = true, hasIdentity = true;
  bool failLoading = false;
  String? consentVersion;
  int sends = 0, evidenceReads = 0;
  Completer<void>? loadGate;
  Completer<void>? evidenceGate;
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
    if (failLoading) throw const IdentityFailure('โหลดข้อมูลไม่ได้');
    return IdentityAccountDetails({
      'fields': fields,
      'has_identity': hasIdentity,
      'selfie_with_card': selfieWithCard,
      if (hasIdentity || pending)
        'evidence': [
          {'kind': 'card', 'id': 'card'},
          {'kind': 'selfie', 'id': 'selfie'},
        ],
      'status': {
        if (hasIdentity) 'profile': {'status': 'approved'},
        if (pending || hasIdentity)
          'request': {
            'status': pending ? 'pending' : 'approved',
            'consent_version': consentVersion,
          },
      },
    });
  }

  @override
  Future<Uint8List> accountEvidence(String id) async {
    evidenceReads++;
    await evidenceGate?.future;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
  }

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
    consentVersion = 'identity-v2';
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

class CountingAddresses extends Addresses {
  int loads = 0;

  @override
  Future<List<ThaiProvince>> load() {
    loads++;
    return super.load();
  }
}

Future<IdentityAccountCubit> open(
  WidgetTester tester,
  AccountRepository repo, {
  bool acceptConsent = true,
  ThaiAddressRepository? addresses,
  String userId = 'account-a',
}) async {
  final cubit = IdentityAccountCubit(
    repo,
    consentStore: IdentityConsentPreferences(userId),
  );
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
                  child: IdentityAccountPage(
                    addressRepository: addresses ?? Addresses(),
                  ),
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
  addTearDown(cubit.close);
  if (acceptConsent) await acceptIdentityConsent(tester);
  return cubit;
}

Future<void> acceptIdentityConsent(WidgetTester tester) async {
  final checkbox = find.byType(CheckboxListTile);
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
  final accept = find.text('ยินยอมและดำเนินการต่อ');
  await tester.ensureVisible(accept);
  await tester.tap(accept);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('เลือกที่อยู่ได้ก่อนโหลดรูปหลักฐานเสร็จ', (tester) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final repo = AccountRepository()..evidenceGate = gate;
    for (final field in [
      'province',
      'district',
      'subdistrict',
      'postal_code',
    ]) {
      repo.fields.remove(field);
    }
    final cubit = await open(tester, repo, acceptConsent: false);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('ยินยอมและดำเนินการต่อ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.evidenceReads, 2);
    expect(cubit.state.photos, isEmpty);

    const selection = {
      'province': 'กรุงเทพมหานคร',
      'district': 'เขตพระนคร',
      'subdistrict': 'พระบรมมหาราชวัง',
    };
    for (final choice in selection.entries) {
      final field = find.byKey(ValueKey(choice.key));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(ValueKey('address_option:${choice.value}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
    expect(cubit.state.photos, isEmpty);
    final save = find.widgetWithText(AppPrimaryButton, 'บันทึกข้อมูล');
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(cubit.state.photos, hasLength(2));
    for (final field in {...selection, 'postal_code': '10200'}.entries) {
      final input = tester.widget<TextFormField>(
        find.byKey(ValueKey(field.key)),
      );
      expect(input.controller!.text, field.value, reason: field.key);
    }
  });

  testWidgets('เลื่อนเงื่อนไขได้ขณะหน้าด้านหลังพักการโหลดรูปและที่อยู่', (
    tester,
  ) async {
    final repo = AccountRepository();
    final addresses = CountingAddresses();
    final cubit = await open(
      tester,
      repo,
      acceptConsent: false,
      addresses: addresses,
    );

    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    expect(dialog, findsOneWidget);
    expect(cubit.state.details, isNotNull);
    expect(repo.evidenceReads, 0);
    expect(addresses.loads, 0);
    expect(
      TickerMode.of(tester.element(find.byType(SkeletonShimmer))),
      isFalse,
    );
    expect(find.byKey(const ValueKey('citizen_id')), findsNothing);
    final heading = find.text('1. ข้อมูลที่เก็บ');
    final sectionTop = tester.getTopLeft(heading).dy;
    await tester.drag(
      find.descendant(of: dialog, matching: find.byType(SingleChildScrollView)),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(heading).dy, lessThan(sectionTop));

    await acceptIdentityConsent(tester);
    expect(repo.evidenceReads, 2);
    expect(addresses.loads, 1);
    expect(find.byKey(const ValueKey('citizen_id')), findsOneWidget);
  });

  testWidgets('ต้องติ๊กยินยอมก่อนบันทึกการแก้ไขข้อมูลบัตรที่มีอยู่', (
    tester,
  ) async {
    final repo = AccountRepository()..consentVersion = 'identity-v1';
    await open(tester, repo, acceptConsent: false);
    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    final checkbox = find.byType(CheckboxListTile);
    final accept = find.widgetWithText(
      AppPrimaryButton,
      'ยินยอมและดำเนินการต่อ',
    );
    expect(dialog, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    expect(tester.widget<AppPrimaryButton>(accept).onPressed, isNull);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<AppPrimaryButton>(accept).onPressed, isNotNull);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<AppPrimaryButton>(accept).onPressed, isNull);
    final decline = find.text('ไว้ก่อน');
    await tester.ensureVisible(decline);
    await tester.tap(decline);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    final firstName = find.byKey(const ValueKey('first_name'));
    await tester.ensureVisible(firstName);
    await tester.enterText(firstName, 'ชื่อใหม่');
    await tester.pump();
    final save = find.widgetWithText(AppPrimaryButton, 'บันทึกข้อมูล');
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);
    expect(repo.sends, 0);

    await tester.tap(find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
    await acceptIdentityConsent(tester);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันส่งข้อมูล'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(repo.fields['first_name'], 'ชื่อใหม่');
  });

  testWidgets('คำขอเดิมที่รอตรวจสอบยังอ่านเงื่อนไขได้', (tester) async {
    final repo = AccountRepository()..pending = true;
    await open(tester, repo, acceptConsent: false);
    expect(
      find.byKey(const ValueKey('identity_consent_dialog')),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    final close = find.text('เข้าใจแล้ว');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ข้อมูลใหม่จะมีผลเมื่อเจ้าหน้าที่อนุมัติ'),
      findsOneWidget,
    );
    final save = find.widgetWithText(AppPrimaryButton, 'รอตรวจสอบ');
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);
    expect(repo.sends, 0);
  });

  testWidgets('คำขอแรกที่รอตรวจสอบและยินยอมแล้วไม่แสดงเงื่อนไข', (
    tester,
  ) async {
    final repo = AccountRepository()
      ..hasIdentity = false
      ..pending = true
      ..consentVersion = 'identity-v2';
    await open(tester, repo, acceptConsent: false);
    expect(find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'), findsNothing);
    final save = find.widgetWithText(AppPrimaryButton, 'รอตรวจสอบ');
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);
  });

  testWidgets('new users verify from account form', (tester) async {
    final repo = AccountRepository()..hasIdentity = false;
    repo.fields.clear();
    await open(tester, repo);
    expect(find.text('ข้อมูลของคุณ ดูแลได้ง่าย ๆ'), findsNothing);
    expect(find.text('ยืนยันตัวตนด้วยบัตรประชาชน'), findsNothing);
    expect(
      find.textContaining('อัปเดตข้อมูลให้ตรงกับบัตรประชาชน'),
      findsNothing,
    );
    expect(find.text('รูปคู่บัตรประชาชน'), findsOneWidget);
    expect(find.text('เลือกคำนำหน้าชื่อ'), findsOneWidget);
    const placeholders = {
      'first_name': 'ชื่อตามบัตรประชาชน',
      'last_name': 'นามสกุลตามบัตรประชาชน',
      'citizen_id': 'เลขบัตร 13 หลัก',
      'birth_date': 'วัน/เดือน/ปี ค.ศ.',
      'address_detail': 'บ้านเลขที่ หมู่ ซอย ถนน',
      'province': 'เลือกจังหวัด',
      'district': 'เลือกอำเภอ/เขต',
      'subdistrict': 'เลือกตำบล/แขวง',
      'postal_code': 'รหัสไปรษณีย์ 5 หลัก',
    };
    for (final entry in placeholders.entries) {
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey(entry.key)),
          matching: find.byType(TextField),
        ),
      );
      expect(field.decoration?.hintText, entry.value, reason: entry.key);
      expect(field.controller?.text, isEmpty, reason: entry.key);
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('citizen_id')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('citizen_id')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('citizen_id')),
      '1101700207030',
    );
    expect(field.controller!.text, '1101700207030');
    expect(field.validator!('123'), isNotNull);
    expect(field.validator!('1234567890123'), isNull);
    expect(field.validator!('1101700207030'), isNull);
  });

  testWidgets('บัญชีอนุมัติที่ยินยอมแล้วเปิดหน้าได้โดยไม่มีเงื่อนไข', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = AccountRepository()
      ..loadGate = gate
      ..consentVersion = 'identity-v2';
    final cubit = IdentityAccountCubit(
      repo,
      consentStore: IdentityConsentPreferences('account-a'),
    );
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
    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    expect(dialog, findsNothing);
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
    final save = find.widgetWithText(AppPrimaryButton, 'บันทึกข้อมูล');
    expect(tester.widget<AppPrimaryButton>(save).isLoading, isFalse);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    final buttonRect = tester.getRect(save);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShimmer), findsNothing);
    expect(dialog, findsNothing);
    expect(tester.getRect(save), buttonRect);
    expect(find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
    await tester.enterText(
      find.byKey(const ValueKey('first_name')),
      'ชื่อใหม่',
    );
    await tester.pump();
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNotNull);
  });

  testWidgets('โหลดไม่สำเร็จแสดงให้ลองใหม่ก่อนตรวจความยินยอม', (tester) async {
    final repo = AccountRepository()..failLoading = true;
    await open(tester, repo, acceptConsent: false);
    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    expect(dialog, findsNothing);
    expect(find.text('โหลดข้อมูลไม่ได้'), findsOneWidget);
    final retry = find.text('ลองอีกครั้ง');
    expect(retry, findsOneWidget);

    repo.failLoading = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(dialog, findsOneWidget);
    await acceptIdentityConsent(tester);
    expect(dialog, findsNothing);
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

  testWidgets('จำการยินยอมเมื่อกลับเข้าหน้าใหม่ก่อนส่งคำขอ', (tester) async {
    final repo = AccountRepository()..consentVersion = 'identity-v1';
    await open(tester, repo);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(repo.sends, 0);

    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    await open(tester, AccountRepository(), acceptConsent: false);
    expect(find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'), findsNothing);
  });

  testWidgets('ความยินยอมบนเครื่องแยกตามบัญชีและเวอร์ชัน', (tester) async {
    SharedPreferences.setMockInitialValues({
      'identity_consent.identity-v1.account-a': true,
    });
    await open(tester, AccountRepository());
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await open(
      tester,
      AccountRepository(),
      acceptConsent: false,
      userId: 'account-b',
    );
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('สลับไปบัญชีที่ยังไม่ส่งคำขอแล้วต้องติ๊กยินยอม', (tester) async {
    SharedPreferences.setMockInitialValues({
      'identity_consent.identity-v2.account-b': true,
    });
    await open(tester, AccountRepository());
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final accountB = AccountRepository()..hasIdentity = false;
    accountB.fields.clear();
    await open(tester, accountB, acceptConsent: false, userId: 'account-b');

    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    final checkbox = find.descendant(
      of: dialog,
      matching: find.byType(CheckboxListTile),
    );
    expect(dialog, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
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

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    await open(tester, repo, acceptConsent: false);
    expect(find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'), findsNothing);
    expect(find.widgetWithText(AppPrimaryButton, 'รอตรวจสอบ'), findsOneWidget);
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
    await tester.runAsync(
      () =>
          (FontLoader('Prompt')
                ..addFont(rootBundle.load('assets/fonts/Prompt-Regular.ttf'))
                ..addFont(rootBundle.load('assets/fonts/Prompt-Bold.ttf')))
              .load(),
    );
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, AccountRepository(), acceptConsent: false);
    final dialog = find.byKey(const ValueKey('identity_consent_dialog'));
    final fixed = [
      find.descendant(
        of: dialog,
        matching: find.text('เงื่อนไขการเก็บข้อมูลบัตรประชาชน'),
      ),
      find.byType(CheckboxListTile),
      find.text('ยินยอมและดำเนินการต่อ'),
      find.text('ไว้ก่อน'),
    ];
    for (final control in fixed) {
      expect(control.hitTestable(), findsOneWidget);
    }
    final fixedPositions = fixed.map(tester.getRect).toList();
    final firstSection = find.text('1. ข้อมูลที่เก็บ');
    final sectionPosition = tester.getTopLeft(firstSection).dy;
    await tester.drag(
      find.descendant(of: dialog, matching: find.byType(SingleChildScrollView)),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstSection).dy, lessThan(sectionPosition));
    expect(fixed.map(tester.getRect).toList(), fixedPositions);
    expect(tester.takeException(), isNull);

    await acceptIdentityConsent(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
