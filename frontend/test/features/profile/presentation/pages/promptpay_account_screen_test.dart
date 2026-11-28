import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/services/skeleton_layout_cache.dart';
import 'package:frontend/features/profile/data/repositories/promptpay_account_repository.dart';
import 'package:frontend/features/profile/presentation/bloc/promptpay_account_cubit.dart';
import 'package:frontend/features/profile/presentation/pages/account/promptpay_account_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  const path = '/api/user/promptpay';
  const headers = {'Authorization': 'Bearer user-token'};

  setUp(() => AuthSession.saveAccessToken('user-token'));
  tearDown(AuthSession.clear);

  Future<void> openScreen(
    WidgetTester tester,
    ApiClient api, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BlocProvider(
          create: (_) =>
              PromptPayAccountCubit(PromptPayAccountRepository(apiClient: api))
                ..load(),
          child: const PromptPayAccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps save accessible above the keyboard on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final api = _MockApiClient();
    const phone = '0812345678';
    when(() => api.get(path, headers: headers)).thenAnswer(
      (_) async =>
          const ApiResponse(statusCode: 200, data: <String, dynamic>{}),
    );
    when(
      () => api.put(path, headers: headers, data: {'promptpay_phone': phone}),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'promptpay_id_type': 'phone', 'promptpay_phone': phone},
      ),
    );

    await openScreen(tester, api, textScale: 1.8);
    expect(find.text('รับค่าเช่าผ่านพร้อมเพย์'), findsNothing);
    final field = find.byType(TextFormField);
    await tester.ensureVisible(field);
    await tester.enterText(field, phone);
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();

    final save = find.text('บันทึกพร้อมเพย์').hitTestable();
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('บันทึกพร้อมเพย์แล้ว'), findsOneWidget);
  });

  testWidgets(
    'switches the saved phone to a national ID and clears the input',
    (tester) async {
      final api = _MockApiClient();
      when(() => api.get(path, headers: headers)).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {'promptpay_id_type': 'phone', 'promptpay_phone': '0812345678'},
        ),
      );
      const data = {'promptpay_national_id': '1234567890121'};
      when(() => api.put(path, headers: headers, data: data)).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {
            'promptpay_id_type': 'national_id',
            'national_id_last_four': '0121',
          },
        ),
      );

      await openScreen(tester, api);
      final field = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        '0812345678',
      );
      await tester.tap(find.text('เลขบัตรประชาชน'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);

      await tester.enterText(field, '123');
      await tester.tap(find.text('บันทึกพร้อมเพย์'));
      await tester.pumpAndSettle();
      expect(find.text('กรุณากรอกเลขบัตรประชาชน 13 หลัก'), findsOneWidget);
      verifyNever(
        () => api.put(
          any(),
          headers: any(named: 'headers'),
          data: any(named: 'data'),
        ),
      );

      await tester.enterText(field, '1234567890121');
      await tester.tap(find.text('บันทึกพร้อมเพย์'));
      await tester.pumpAndSettle();
      verify(() => api.put(path, headers: headers, data: data)).called(1);
      expect(find.textContaining('0121'), findsOneWidget);
      expect(find.text('1234567890121'), findsNothing);
      expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
      expect(find.text('บันทึกพร้อมเพย์แล้ว'), findsOneWidget);
    },
  );

  testWidgets('retries loading and preserves the form after a failed save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _MockApiClient();
    var loadAttempts = 0;
    when(() => api.get(path, headers: headers)).thenAnswer((_) async {
      if (loadAttempts++ == 0) {
        throw const ApiClientException(ApiClientErrorType.connection);
      }
      return const ApiResponse(statusCode: 200, data: <String, dynamic>{});
    });
    const data = {'promptpay_phone': '0891234567'};
    when(
      () => api.put(path, headers: headers, data: data),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 500, data: {}));

    await openScreen(tester, api, textScale: 1.8);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    await tester.enterText(field, '0891234567');
    await tester.tap(find.text('บันทึกพร้อมเพย์'));
    await tester.pumpAndSettle();

    verify(() => api.put(path, headers: headers, data: data)).called(1);
    expect(find.text('บันทึกพร้อมเพย์ไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(tester.widget<TextFormField>(field).controller!.text, '0891234567');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'replaces an unreadable ID and clears the error when switching type',
    (tester) async {
      final api = _MockApiClient();
      when(() => api.get(path, headers: headers)).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {'promptpay_id_type': 'national_id'},
        ),
      );
      when(
        () => api.put(
          path,
          headers: headers,
          data: {'promptpay_national_id': '1234567890122'},
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 400,
          data: {'error': 'เลขบัตรประชาชนไม่ถูกต้อง'},
        ),
      );
      when(
        () => api.put(
          path,
          headers: headers,
          data: {'promptpay_phone': '0891234567'},
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {'promptpay_id_type': 'phone', 'promptpay_phone': '0891234567'},
        ),
      );

      await openScreen(tester, api);
      expect(find.text('เลขบัตรประชาชนที่ผูกพร้อมเพย์'), findsOneWidget);
      final field = find.byType(TextFormField);
      await tester.enterText(field, '1234567890122');
      await tester.tap(find.text('บันทึกพร้อมเพย์'));
      await tester.pumpAndSettle();
      expect(find.text('เลขบัตรประชาชนไม่ถูกต้อง'), findsOneWidget);

      await tester.tap(find.text('เบอร์มือถือ'));
      await tester.pumpAndSettle();
      expect(find.text('เลขบัตรประชาชนไม่ถูกต้อง'), findsNothing);
      await tester.enterText(field, '0891234567');
      await tester.tap(find.text('บันทึกพร้อมเพย์'));
      await tester.pumpAndSettle();
      expect(find.text('บันทึกพร้อมเพย์แล้ว'), findsOneWidget);
    },
  );

  for (final nationalId in [false, true]) {
    testWidgets(
      'loading skeleton lines up with the loaded form (nationalId: $nationalId)',
      (tester) async {
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _MockApiClient();
        final response = Completer<ApiResponse>();
        when(
          () => api.get(path, headers: headers),
        ).thenAnswer((_) => response.future);
        // จำว่าบัญชีนี้ใช้ประเภทไหน เหมือนเคยเปิดหน้านี้มาก่อน
        SkeletonLayoutCache.instance.write('promptpay.${AuthSession.userId}', [
          nationalId ? 'n' : 'p',
          nationalId ? '4' : '-',
          '-',
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider(
              create: (_) => PromptPayAccountCubit(
                PromptPayAccountRepository(apiClient: api),
              )..load(),
              child: const PromptPayAccountScreen(),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('promptpay-loading-skeleton')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        Rect rectOf(Finder finder) => tester.getRect(finder.first);
        final skeleton = (
          segments: rectOf(find.byType(SegmentedButton<bool>)),
          field: rectOf(find.byType(InputDecorator)),
        );

        response.complete(
          ApiResponse(
            statusCode: 200,
            data: nationalId
                ? {
                    'promptpay_id_type': 'national_id',
                    'national_id_last_four': '1234',
                  }
                : <String, dynamic>{},
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('promptpay-loading-skeleton')),
          findsNothing,
        );
        expect(rectOf(find.byType(SegmentedButton<bool>)), skeleton.segments);
        expect(rectOf(find.byType(InputDecorator)), skeleton.field);
      },
    );
  }
}
