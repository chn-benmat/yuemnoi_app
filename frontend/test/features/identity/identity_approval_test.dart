import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/domain/identity_repository.dart';
import 'package:frontend/features/identity/presentation/identity_cubit.dart';
import 'package:frontend/features/identity/presentation/identity_page.dart';
import 'package:mocktail/mocktail.dart';

class _IdentityRepository extends Mock implements IdentityRepository {}

void main() {
  test('ผลอนุมัติที่ไม่ระบุวันหมดอายุยังยืนยันตัวตนแล้ว', () {
    expect(
      const IdentityStatus({
        'profile': {
          'status': 'approved',
          'lifetime': false,
          'expires_on': null,
        },
      }).verified,
      isTrue,
    );
  });

  test('ผลอนุมัติไม่ขึ้นกับวันหมดอายุบัตรเดิม', () {
    final today = DateTime.now();
    final todayText =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    for (final entry in {
      '2000-01-01': true,
      todayText: true,
      '9999-12-31': true,
      'invalid-date': true,
    }.entries) {
      expect(
        IdentityStatus({
          'profile': {
            'status': 'approved',
            'lifetime': false,
            'expires_on': entry.key,
          },
        }).verified,
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      const IdentityStatus({
        'profile': {'status': 'revoked', 'expires_on': null},
      }).verified,
      isFalse,
    );
  });

  testWidgets('อนุมัติโดยเจ้าหน้าที่โดยไม่ระบุวันหมดอายุต้องไม่ให้ยืนยันใหม่', (
    tester,
  ) async {
    final repository = _IdentityRepository();
    when(() => repository.status()).thenAnswer(
      (_) async => const IdentityStatus({
        'available': true,
        'can_list': true,
        'profile': {
          'status': 'approved',
          'lifetime': false,
          'expires_on': null,
        },
      }),
    );
    final cubit = IdentityCubit(repository);
    addTearDown(cubit.close);
    await cubit.load();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: cubit, child: const IdentityPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ต้องยืนยันใหม่'), findsNothing);
    expect(find.text('ยืนยันตัวตนแล้ว'), findsOneWidget);
    expect(find.text('เริ่มยืนยันตัวตนใหม่'), findsNothing);
    expect(find.text('ใช้ได้ถึง'), findsNothing);
    expect(find.text('ไม่ได้ระบุวันหมดอายุ'), findsNothing);
    expect(find.text('บัตรตลอดชีพ'), findsNothing);
    expect(find.text('เลือกวัน เดือน ปี'), findsNothing);
    expect(find.text('ไปลงสินค้าให้เช่า'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
