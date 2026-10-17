import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/data/asset_thai_address_repository.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/domain/thai_address.dart';
import 'package:frontend/features/identity/presentation/identity_cubit.dart';
import 'package:frontend/features/identity/presentation/identity_page.dart';
import 'package:frontend/features/identity/presentation/widgets/identity_camera_page.dart';

late List<ThaiProvince> _thaiProvinces;

class _TestAddressRepository implements ThaiAddressRepository {
  bool fail = false;

  @override
  Future<List<ThaiProvince>> load() async {
    if (fail) throw StateError('อ่าน asset ไม่สำเร็จ');
    return _thaiProvinces;
  }
}

class RolloutRepository implements IdentityRepository {
  RolloutRepository({Map<String, dynamic>? data})
    : data = data ?? {'available': true};
  Map<String, dynamic> data;
  int begins = 0, submits = 0;
  String? beganWithBirthDate;
  bool failSubmit = false, failBegin = false;
  Map<String, String>? submittedFields;
  @override
  Future<IdentityStatus> status() async => IdentityStatus(data);
  @override
  Future<Map<String, dynamic>> begin(String birthDate) async {
    begins++;
    beganWithBirthDate = birthDate;
    if (failBegin) throw const IdentityFailure('เริ่มคำขอไม่สำเร็จ');
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
  Future<void> submit(
    String session,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  ) async {
    submits++;
    submittedFields = Map.of(fields);
    if (failSubmit) throw const IdentityFailure('ส่งไม่สำเร็จ ข้อมูลยังอยู่');
    data = {
      ...data,
      'request': {'id': session, 'status': 'pending'},
    };
  }

  @override
  void close() {}
}

Future<RolloutRepository> showPage(
  WidgetTester tester, {
  RolloutRepository? repository,
  double scale = 1,
  IdentityCapture? capture,
  bool acceptConsent = true,
  ThaiAddressRepository? addressRepository,
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
          addressRepository: addressRepository ?? _TestAddressRepository(),
          capture:
              capture ??
              (context, kind) async => base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY7h8+fJ/AAhvA3nL6ibXAAAAAElFTkSuQmCC',
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (acceptConsent &&
      find.text('ยินยอมและดำเนินการต่อ').evaluate().isNotEmpty) {
    await tapText(tester, 'ยินยอมและดำเนินการต่อ');
  }
  return repo;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> selectBirthDate(
  WidgetTester tester, {
  int year = 2000,
  int month = 1,
  int day = 1,
}) async {
  final field = find.byKey(const ValueKey('pick_birth_date'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  for (final change in {2: year, 1: month, 0: day}.entries) {
    tester
        .widget<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>).at(change.key),
        )
        .onChanged!(change.value);
    await tester.pumpAndSettle();
  }
  await tapText(tester, 'ใช้วันที่นี้');
}

Future<void> begin(WidgetTester tester, {int birthYear = 2000}) async {
  if (find.text('ยินยอมและดำเนินการต่อ').evaluate().isNotEmpty) {
    await tapText(tester, 'ยินยอมและดำเนินการต่อ');
  }
  await tapText(tester, 'ถ่ายบัตรและใบหน้า');
  await selectBirthDate(tester, year: birthYear);
}

Future<void> photos(WidgetTester tester) async {
  expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
}

Future<void> confirm(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final tile = find.byKey(const ValueKey('identity_confirmation'));
  await tester.ensureVisible(tile);
  if (!tester.widget<CheckboxListTile>(tile).value!) {
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }
  expect(tester.widget<CheckboxListTile>(tile).value, true);
}

Uint8List testPhoto() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY7h8+fJ/AAhvA3nL6ibXAAAAAElFTkSuQmCC',
);

Future<void> fillAddress(WidgetTester tester) async {
  final detail = find.byKey(const ValueKey('address_detail'));
  await tester.ensureVisible(detail);
  await tester.enterText(detail, '99/1 หมู่ 2 ถนนทดสอบ');
  for (final entry in {
    'province': 'กรุงเทพมหานคร',
    'district': 'พระนคร',
    'subdistrict': 'บวรนิเวศ',
  }.entries) {
    await selectAddress(tester, entry.key, entry.value);
  }
  await tester.pumpAndSettle();
}

Future<void> selectAddress(
  WidgetTester tester,
  String field,
  String value,
) async {
  final target = find.byKey(ValueKey(field));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('address_search')), value);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('address_option:$value')));
  await tester.pumpAndSettle();
}

Future<void> fillIdentity(
  WidgetTester tester, {
  String prefix = 'นาย',
  int birthYear = 2000,
  bool includeBirthDate = true,
}) async {
  await tapText(tester, prefix);
  for (final entry in {
    'first_name': 'ทดสอบ',
    'last_name': 'ระบบ',
    'citizen_id': '0000000000001',
  }.entries) {
    final field = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
  if (includeBirthDate) await selectBirthDate(tester, year: birthYear);
  await fillAddress(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _thaiProvinces = await AssetThaiAddressRepository().load();
  });

  testWidgets(
    'เลือกพื้นที่ตามลำดับ ค้นหาได้ และเปลี่ยนพื้นที่ล้างข้อมูลที่ขึ้นต่อกัน',
    (tester) async {
      await showPage(tester);
      String text(String field) => tester
          .widget<TextFormField>(find.byKey(ValueKey(field)))
          .controller!
          .text;
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('district')))
            .enabled,
        false,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('province')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        true,
      );
      await fillAddress(tester);
      expect(text('postal_code'), '10200');
      await confirm(tester);
      await selectAddress(tester, 'district', 'หนองแขม');
      expect(text('province'), 'กรุงเทพมหานคร');
      expect(text('district'), 'หนองแขม');
      expect(text('subdistrict'), isEmpty);
      expect(text('postal_code'), isEmpty);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('identity_confirmation')),
            )
            .value,
        false,
      );
      await selectAddress(tester, 'subdistrict', 'หนองแขม');
      expect(text('postal_code'), '10160');
      await selectAddress(tester, 'province', 'เชียงใหม่');
      expect(text('district'), isEmpty);
      expect(text('subdistrict'), isEmpty);
      expect(text('postal_code'), isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('subdistrict')))
            .enabled,
        false,
      );
      await selectAddress(tester, 'district', 'เมืองเชียงใหม่');
      await selectAddress(tester, 'subdistrict', 'ศรีภูมิ');
      expect(text('postal_code'), '50200');

      final province = find.byKey(const ValueKey('province'));
      await tester.ensureVisible(province);
      await tester.tap(province);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('address_search'));
      await tester.enterText(search, 'ไม่มีจังหวัดชื่อนี้');
      await tester.pumpAndSettle();
      expect(find.text('ไม่พบข้อมูลที่ค้นหา'), findsOneWidget);
      await tester.enterText(search, 'ภูเก็ต');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('address_option:ภูเก็ต')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('address_option:กรุงเทพมหานคร')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('ปิดรายการ'));
      await tester.pumpAndSettle();
      expect(text('province'), 'เชียงใหม่');
      expect(text('postal_code'), '50200');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'รหัสหลายตัวเลือกแก้เองได้ เก็บค่าตอนเปิดซ้ำ และส่งค่าที่แก้จริง',
    (tester) async {
      final repo = await showPage(tester);
      await begin(tester);
      await fillIdentity(tester);
      await selectAddress(tester, 'district', 'ดุสิต');
      await selectAddress(tester, 'subdistrict', 'สวนจิตรลดา');
      final postal = find.byKey(const ValueKey('postal_code'));
      String code() => tester.widget<TextFormField>(postal).controller!.text;
      expect(code(), '10300');
      final option = find.byKey(const ValueKey('postal_option:10303'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(code(), '10303');
      await confirm(tester);
      await tester.ensureVisible(postal);
      await tester.enterText(postal, '10301');
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(option).selected, false);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('identity_confirmation')),
            )
            .value,
        false,
      );
      await selectAddress(tester, 'subdistrict', 'สวนจิตรลดา');
      expect(code(), '10301');
      await confirm(tester);
      await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
      expect(repo.submittedFields!['postal_code'], '10301');
      expect(repo.submittedFields!['district'], 'ดุสิต');
      expect(repo.submittedFields!['subdistrict'], 'สวนจิตรลดา');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('โหลดข้อมูลพื้นที่ล้มเหลวลองใหม่ได้โดยไม่ล้างข้อมูลส่วนตัว', (
    tester,
  ) async {
    final repository = _TestAddressRepository()..fail = true;
    await showPage(tester, addressRepository: repository);
    final firstName = find.byKey(const ValueKey('first_name'));
    await tester.ensureVisible(firstName);
    await tester.enterText(firstName, 'ทดสอบ');
    expect(find.text('โหลดรายการที่อยู่ไม่สำเร็จ'), findsOneWidget);
    repository.fail = false;
    await tapText(tester, 'ลองอีกครั้ง');
    await fillAddress(tester);
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('10200'), findsOneWidget);
    expect(find.text('โหลดรายการที่อยู่ไม่สำเร็จ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('กล้องถูกปฏิเสธสิทธิ์มีปุ่มตั้งค่าและลองใหม่', (tester) async {
    const camera = MethodChannel('plugins.flutter.io/camera');
    const permission = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(camera, (call) async {
      throw PlatformException(code: 'CameraAccessDenied');
    });
    messenger.setMockMethodCallHandler(permission, (call) async => false);
    addTearDown(() {
      messenger.setMockMethodCallHandler(camera, null);
      messenger.setMockMethodCallHandler(permission, null);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: IdentityCameraPage(kind: IdentityCaptureKind.card),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('บัตรประชาชน · รูปที่ 1 จาก 2'), findsOneWidget);
    expect(find.text('ลองเปิดกล้องอีกครั้ง'), findsOneWidget);
    await tapText(tester, 'เปิดการตั้งค่ากล้อง');
    expect(find.textContaining('เปิดตั้งค่าไม่ได้'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('เริ่มจากฟอร์มถ่ายบัตรต่อใบหน้าแล้วกลับฟอร์มเดิม ไม่มี OCR', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    final repo = await showPage(
      tester,
      capture: (context, kind) async {
        captures.add(kind);
        return testPhoto();
      },
    );
    await begin(tester);
    expect(repo.begins, 0);
    expect(find.text('1 ม.ค. 2543'), findsOneWidget);
    expect(find.text('อายุครบ 20 ปีหรือยัง?'), findsNothing);
    expect(captures, [IdentityCaptureKind.card, IdentityCaptureKind.selfie]);
    expect(find.text('ขั้นตอน 3 / 3'), findsNothing);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    expect(find.text('ตรวจสรุปก่อนส่ง'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('first_name')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('ลองอ่านข้อมูลอีกครั้ง'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ยกเลิกถ่ายใบหน้าแล้วทำต่อได้โดยไม่ถ่ายบัตรซ้ำ', (tester) async {
    final captures = <IdentityCaptureKind>[];
    var cancelFace = true;
    await showPage(
      tester,
      capture: (context, kind) async {
        captures.add(kind);
        if (kind == IdentityCaptureKind.selfie && cancelFace) return null;
        return testPhoto();
      },
    );
    await begin(tester);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    cancelFace = false;
    await tapText(tester, 'ถ่ายใบหน้า');
    expect(captures, [
      IdentityCaptureKind.card,
      IdentityCaptureKind.selfie,
      IdentityCaptureKind.selfie,
    ]);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ยกเลิกถ่ายบัตรไม่เปิดกล้องหน้าและกลับมาถ่ายต่อได้', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    var cancelled = true;
    await showPage(
      tester,
      capture: (context, kind) async {
        captures.add(kind);
        return cancelled ? null : testPhoto();
      },
    );
    await begin(tester);
    expect(captures, [IdentityCaptureKind.card]);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    cancelled = false;
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(captures, [
      IdentityCaptureKind.card,
      IdentityCaptureKind.card,
      IdentityCaptureKind.selfie,
    ]);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('กล้องผิดพลาดแสดงทางทำต่อโดยไม่เริ่ม session ใหม่', (
    tester,
  ) async {
    var fail = true;
    final repo = await showPage(
      tester,
      capture: (context, kind) async {
        if (fail) throw Exception('camera');
        return testPhoto();
      },
    );
    await begin(tester);
    expect(find.textContaining('เปิดกล้องไม่สำเร็จ'), findsOneWidget);
    fail = false;
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(repo.begins, 0);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('วันเกิดหลังถ่ายภาพปรับวันให้ตรงเดือนและปีที่เลือก', (
    tester,
  ) async {
    await showPage(tester);
    await begin(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('pick_birth_date')));
    await tester.tap(find.byKey(const ValueKey('pick_birth_date')));
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

  testWidgets('เปิดฟอร์มทันทีพร้อมป๊อปอัพและยินยอมแล้วไม่เปิดกล้อง', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    final repo = await showPage(
      tester,
      acceptConsent: false,
      capture: (context, kind) async {
        captures.add(kind);
        return testPhoto();
      },
    );
    expect(
      find.byKey(const ValueKey('identity_consent_dialog')),
      findsOneWidget,
    );
    expect(
      find.textContaining('เพื่อให้เจ้าหน้าที่ที่ได้รับสิทธิ์ตรวจสอบ'),
      findsOneWidget,
    );
    expect(find.text('ยืนยันตัวตนให้พร้อมปล่อยเช่า'), findsNothing);
    expect(find.text('อายุครบ 20 ปีหรือยัง?'), findsNothing);
    expect(repo.begins, 0);
    expect(captures, isEmpty);
    await tapText(tester, 'ยินยอมและดำเนินการต่อ');
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    expect(find.byKey(const ValueKey('pick_birth_date')), findsOneWidget);
    expect(repo.begins, 0);
    expect(captures, isEmpty);
    await tester
        .element(find.byType(IdentityPage))
        .read<IdentityCubit>()
        .load();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('identity_consent_dialog')), findsNothing);
    await tapText(tester, 'เงื่อนไขการใช้ข้อมูล');
    expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    await tapText(tester, 'เข้าใจแล้ว');
    expect(repo.begins, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ปิดป๊อปอัพข้ามความยินยอมไม่ได้และไว้ก่อนกลับหน้าบัญชี', (
    tester,
  ) async {
    var captures = 0;
    final repo = RolloutRepository();
    final cubit = IdentityCubit(repo);
    addTearDown(cubit.close);
    await cubit.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider.value(
                    value: cubit,
                    child: IdentityPage(
                      capture: (context, kind) async {
                        captures++;
                        return testPhoto();
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('เปิดจากหน้าบัญชี'),
            ),
          ),
        ),
      ),
    );
    await tapText(tester, 'เปิดจากหน้าบัญชี');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('identity_consent_dialog')),
      findsOneWidget,
    );
    await tapText(tester, 'ไว้ก่อน');
    expect(find.text('เปิดจากหน้าบัญชี'), findsOneWidget);
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsNothing);
    expect(repo.begins, 0);
    expect(captures, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('กรอกก่อนถ่ายได้โดยยังไม่เริ่มคำขอและไม่ล้างช่องกรอก', (
    tester,
  ) async {
    final repo = await showPage(tester);
    await fillIdentity(tester);
    await confirm(tester);
    expect(repo.begins, 0);
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(repo.begins, 0);
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('10200'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('identity_confirmation')),
          )
          .value,
      false,
    );
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.beganWithBirthDate, '2000-01-01');
    expect(repo.submits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ถ่ายต่อเนื่องและถ่ายใหม่จากช่องภาพได้ก่อนกรอกวันเกิด', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    final repo = await showPage(
      tester,
      capture: (context, kind) async {
        captures.add(kind);
        return testPhoto();
      },
    );
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(captures, [IdentityCaptureKind.card, IdentityCaptureKind.selfie]);
    expect(find.text('กรุณาเลือกวันที่'), findsNothing);
    for (final tile in ['card_photo', 'selfie_photo']) {
      final capture = find.descendant(
        of: find.byKey(ValueKey(tile)),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(capture);
      await tester.tap(capture);
      await tester.pumpAndSettle();
    }
    expect(captures, [
      IdentityCaptureKind.card,
      IdentityCaptureKind.selfie,
      IdentityCaptureKind.card,
      IdentityCaptureKind.selfie,
    ]);
    expect(repo.begins, 0);
    expect(repo.submits, 0);
    expect(find.byType(Image), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('กรอกวันเกิดหลังถ่ายภาพแล้วเริ่มและส่งคำขอในครั้งเดียว', (
    tester,
  ) async {
    final repo = await showPage(tester);
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    await fillIdentity(tester);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.beganWithBirthDate, '2000-01-01');
    expect(repo.submits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ถ่ายภาพก่อนได้แต่ต้องกรอกวันเกิดให้ครบเมื่อส่ง', (tester) async {
    final repo = await showPage(tester);
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    await fillIdentity(tester, includeBirthDate: false);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(find.text('กรุณาเลือกวันที่'), findsOneWidget);
    expect(repo.begins, 0);
    expect(repo.submits, 0);
    expect(find.byType(Image), findsNWidgets(2));
    await selectBirthDate(tester);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.submits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final age in [0, 5, 13, 19, 20, 80]) {
    testWidgets('อายุ $age ยืนยันตัวตนได้โดยไม่ต้องเชื่อมผู้ปกครอง', (
      tester,
    ) async {
      final repo = await showPage(
        tester,
        repository: RolloutRepository(
          data: {
            'available': true,
            'control': {'is_minor': true, 'suspended': false},
          },
        ),
      );
      final year = DateTime.now().year - age;
      await fillIdentity(tester, birthYear: year);
      expect(find.text('คัดลอกรหัสให้ผู้ปกครอง'), findsNothing);
      await tapText(tester, 'ถ่ายบัตรและใบหน้า');
      await confirm(tester);
      await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
      expect(repo.begins, 1);
      expect(repo.submits, 1);
      expect(repo.submittedFields!['birth_date'], '$year-01-01');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ผู้เยาว์ส่งคำขอได้โดยไม่มีข้อมูลผู้ปกครอง', (tester) async {
    final year = DateTime.now().year - 10;
    final repo = await showPage(
      tester,
      repository: RolloutRepository(data: {'available': true}),
    );
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(repo.begins, 0);
    await fillIdentity(tester, birthYear: year);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.beganWithBirthDate, '$year-01-01');
    expect(repo.submits, 1);
    expect(repo.submittedFields!['birth_date'], '$year-01-01');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('แก้วันเกิดเก็บภาพและใช้คำขอเดิมเมื่อส่งอีกครั้ง', (
    tester,
  ) async {
    final repo = await showPage(
      tester,
      repository: RolloutRepository(data: {'available': true})
        ..failSubmit = true,
    );
    await begin(tester);
    await fillIdentity(tester);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    final year = DateTime.now().year - 10;
    await selectBirthDate(tester, year: year);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('10200'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('identity_confirmation')),
          )
          .value,
      false,
    );
    repo.failSubmit = false;
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.submits, 2);
    expect(repo.submittedFields!['birth_date'], '$year-01-01');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('วันเกิดอนาคตยังเลือกใช้ไม่ได้', (tester) async {
    final now = DateTime.now().toUtc();
    final future = DateTime(now.year, 12, 31);
    await showPage(tester);
    await begin(tester);
    await tapText(tester, '1 ม.ค. 2543');
    for (final change in {
      2: future.year,
      1: future.month,
      0: future.day,
    }.entries) {
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>).at(change.key),
          )
          .onChanged!(change.value);
      await tester.pumpAndSettle();
    }
    final years = tester.widget<DropdownButton<int>>(
      find.descendant(
        of: find.byType(DropdownButtonFormField<int>).at(2),
        matching: find.byType(DropdownButton<int>),
      ),
    );
    expect(years.items!.any((item) => item.value! > now.year), false);
    if (future.isAfter(DateUtils.dateOnly(now))) {
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'ใช้วันที่นี้'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('ไม่อยู่ในอนาคต'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backend ไม่ให้เริ่มคำขอไม่อัปโหลดและเก็บภาพกับข้อมูลให้ส่งซ้ำ', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    final repo = RolloutRepository()..failBegin = true;
    await showPage(
      tester,
      repository: repo,
      capture: (context, kind) async {
        captures.add(kind);
        return testPhoto();
      },
    );
    await fillIdentity(tester);
    await tapText(tester, 'ถ่ายบัตรและใบหน้า');
    expect(repo.begins, 0);
    expect(captures, [IdentityCaptureKind.card, IdentityCaptureKind.selfie]);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 1);
    expect(repo.submits, 0);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('1 ม.ค. 2543'), findsOneWidget);
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('เริ่มคำขอไม่สำเร็จ'), findsOneWidget);
    repo.failBegin = false;
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.begins, 2);
    expect(captures, [IdentityCaptureKind.card, IdentityCaptureKind.selfie]);
    expect(repo.submittedFields!['postal_code'], '10200');
    expect(repo.submits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final knownAge in [true, false]) {
    testWidgets(
      'กลับเข้ารอบเดิมถ่ายก่อนได้โดยไม่สนใจข้อมูลช่วงอายุเดิม $knownAge ตอนส่ง',
      (tester) async {
        final captures = <IdentityCaptureKind>[];
        final repo = await showPage(
          tester,
          repository: RolloutRepository(
            data: {
              'available': true,
              'request': {
                'id': 'test-session',
                'status': 'capture',
                if (knownAge) 'is_minor': false,
                'capture_until': DateTime.now()
                    .add(const Duration(minutes: 15))
                    .toUtc()
                    .toIso8601String(),
              },
            },
          ),
          capture: (context, kind) async {
            captures.add(kind);
            return testPhoto();
          },
        );
        expect(find.byKey(const ValueKey('pick_birth_date')), findsOneWidget);
        expect(find.text('อายุครบ 20 ปีหรือยัง?'), findsNothing);
        await tapText(tester, 'ถ่ายบัตรและใบหน้า');
        expect(captures, [
          IdentityCaptureKind.card,
          IdentityCaptureKind.selfie,
        ]);
        expect(repo.begins, 0);
        await fillIdentity(tester);
        await confirm(tester);
        await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
        expect(repo.begins, 0);
        expect(repo.submits, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'แก้วันเกิดในหน้าตรวจใช้ค่าใหม่และต้องยืนยันความถูกต้องอีกครั้ง',
    (tester) async {
      final repo = await showPage(tester);
      await begin(tester);
      await fillIdentity(tester);
      await confirm(tester);
      await selectBirthDate(tester, year: 2001, month: 2, day: 3);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('identity_confirmation')),
            )
            .value,
        false,
      );
      await confirm(tester);
      await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
      expect(repo.submittedFields!['birth_date'], '2001-02-03');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ปิด availability ยังจำกัดบัญชีทั่วไป', (tester) async {
    await showPage(
      tester,
      repository: RolloutRepository(data: {'available': false}),
    );
    expect(find.text('ยังเปิดยืนยันไม่ได้'), findsOneWidget);
    expect(find.text('ยินยอมและเริ่มยืนยัน'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ย้อนกลับและโหลดสถานะไม่ล้างข้อมูลหรือรูป', (tester) async {
    final repo = await showPage(tester);
    await begin(tester);
    await fillIdentity(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('first_name')));
    await tester.enterText(find.byKey(const ValueKey('first_name')), 'แก้ไข');
    await tester.tap(find.byTooltip('ย้อนกลับ'));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจข้อมูล แล้วส่งคำขอ'), findsOneWidget);
    await tapText(tester, 'ทำต่อ');
    await tester
        .element(find.byType(IdentityPage))
        .read<IdentityCubit>()
        .load();
    await tester.pumpAndSettle();
    expect(find.text('แก้ไข'), findsOneWidget);
    expect(find.text('10200'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(repo.submits, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ถ่ายบัตรใหม่จากหน้าข้อมูลไม่ล้างช่องกรอกและต้องยืนยันใหม่', (
    tester,
  ) async {
    final captures = <IdentityCaptureKind>[];
    await showPage(
      tester,
      capture: (context, kind) async {
        captures.add(kind);
        return testPhoto();
      },
    );
    await begin(tester);
    await fillIdentity(tester);
    await confirm(tester);
    final retake = find.descendant(
      of: find.byKey(const ValueKey('card_photo')),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(retake);
    await tester.tap(retake);
    await tester.pumpAndSettle();
    expect(captures.last, IdentityCaptureKind.card);
    expect(captures.length, 3);
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('10200'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('identity_confirmation')),
          )
          .value,
      false,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'ส่งคำขอยืนยันตัวตน'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('แก้ข้อมูลหลังยืนยันแล้วต้องยืนยันความถูกต้องใหม่', (
    tester,
  ) async {
    await showPage(tester);
    await begin(tester);
    await fillIdentity(tester);
    await confirm(tester);
    final field = find.byKey(const ValueKey('first_name'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'แก้ไข');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('identity_confirmation')),
          )
          .value,
      false,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'ส่งคำขอยืนยันตัวตน'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ส่งล้มเหลวเก็บข้อมูลและรูปเพื่อส่งซ้ำด้วย contract เดิม', (
    tester,
  ) async {
    final repo = RolloutRepository()..failSubmit = true;
    await showPage(tester, repository: repo);
    await begin(tester);
    await fillIdentity(tester);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 1);
    expect(find.text('ทดสอบ'), findsOneWidget);
    expect(find.text('99/1 หมู่ 2 ถนนทดสอบ'), findsOneWidget);
    expect(find.textContaining('ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    repo.failSubmit = false;
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 2);
    expect(repo.submittedFields, {
      'name_prefix': 'นาย',
      'legal_name': 'นาย ทดสอบ ระบบ',
      'first_name': 'ทดสอบ',
      'last_name': 'ระบบ',
      'citizen_id': '0000000000001',
      'birth_date': '2000-01-01',
      'address_detail': '99/1 หมู่ 2 ถนนทดสอบ',
      'postal_code': '10200',
      'province': 'กรุงเทพมหานคร',
      'district': 'พระนคร',
      'subdistrict': 'บวรนิเวศ',
    });
    expect(find.text('รับคำขอของคุณแล้ว'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('เลขบัตรต้องครบ 13 หลักแล้วส่งให้เจ้าหน้าที่โดยไม่ตรวจสูตร', (
    tester,
  ) async {
    final repo = await showPage(tester);
    await begin(tester);
    await fillIdentity(tester);
    final citizen = find.byKey(const ValueKey('citizen_id'));
    await tester.ensureVisible(citizen);
    await tester.enterText(citizen, '123456789000');
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 0);
    expect(find.text('กรอกเลขบัตร 13 หลักให้ครบ'), findsOneWidget);

    await tester.ensureVisible(citizen);
    await tester.enterText(citizen, '1234567890000');
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 1);
    expect(repo.submittedFields!['citizen_id'], '1234567890000');
    expect(find.text('รับคำขอของคุณแล้ว'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ข้อมูลอื่นยังว่างไม่ส่งและเลื่อนไปข้อผิดพลาดแรก', (
    tester,
  ) async {
    final repo = await showPage(tester);
    await begin(tester);
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 0);
    expect(find.text('กรุณาเลือกคำนำหน้าชื่อ'), findsOneWidget);
    expect(find.text('กรุณากรอกข้อมูลช่องนี้'), findsNWidgets(6));
    expect(find.text('กรุณากรอกรหัสไปรษณีย์ 5 หลักให้ถูกต้อง'), findsOneWidget);
    expect(find.text('กรอกเลขบัตร 13 หลักให้ครบ'), findsOneWidget);
    expect(find.text('กรุณาเลือกวันที่'), findsNothing);
    expect(
      tester.getTopLeft(find.text('กรุณาเลือกคำนำหน้าชื่อ')).dy,
      lessThan(400),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('รหัสไปรษณีย์รับตัวเลขห้าหลักและตรวจข้อมูลก่อนส่ง', (
    tester,
  ) async {
    final repo = await showPage(tester);
    await begin(tester);
    await fillIdentity(tester);
    final postal = find.byKey(const ValueKey('postal_code'));
    await tester.ensureVisible(postal);
    await tester.enterText(postal, '1a020056');
    expect(tester.widget<TextFormField>(postal).controller!.text, '10200');
    await tester.enterText(postal, '1020');
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 0);
    expect(find.text('กรุณากรอกรหัสไปรษณีย์ 5 หลักให้ถูกต้อง'), findsOneWidget);
    await tester.ensureVisible(postal);
    await tester.enterText(postal, '10200');
    await confirm(tester);
    await tapText(tester, 'ส่งคำขอยืนยันตัวตน');
    expect(repo.submits, 1);
    expect(repo.submittedFields, isNot(contains('expires_on')));
    expect(repo.submittedFields, isNot(contains('lifetime')));
    await tester.pumpWidget(const SizedBox());
  });

  for (final prefix in ['นาย', 'นางสาว', 'นาง']) {
    testWidgets('เลือกคำนำหน้า $prefix ได้โดยแตะครั้งเดียว', (tester) async {
      await showPage(tester);
      await begin(tester);
      await fillIdentity(tester, prefix: prefix);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, prefix))
            .selected,
        true,
      );
      expect(find.text('ทดสอบ'), findsOneWidget);
      expect(find.text('ระบบ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('บัญชีที่ผ่านแล้วไม่มีเมนูผู้ปกครอง', (tester) async {
    await showPage(
      tester,
      repository: RolloutRepository(
        data: {
          'available': true,
          'can_list': true,
          'profile': {'status': 'approved', 'lifetime': true, 'is_minor': true},
        },
      ),
    );
    expect(find.text('ดูแลบัญชีผู้เยาว์'), findsNothing);
    expect(find.text('ผ่านการอนุมัติ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [
    'pending',
    'corrections',
    'rejected',
    'expired',
    'approved',
  ]) {
    testWidgets('สถานะ $kind แสดงผลและคำสั่งถัดไป', (tester) async {
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
      expect(find.text('ดูแลบัญชีผู้เยาว์'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('จอ $width และตัวอักษรขยายไม่ล้นทั้งป๊อปอัพและฟอร์ม', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showPage(tester, scale: 1.3, acceptConsent: false);
      expect(tester.takeException(), isNull);
      await begin(tester);
      await fillIdentity(tester);
      await confirm(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
