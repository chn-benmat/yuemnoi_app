import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/profile/data/datasources/rental_management_remote_data_source.dart';
import 'package:frontend/features/profile/data/repositories/rental_management_repository_impl.dart';
import 'package:frontend/features/profile/domain/usecases/get_rental_income_usecase.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_income_screen.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_income_widgets.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  const path = '/api/rentals/income';
  const headers = {'Authorization': 'Bearer owner-token'};

  setUp(() => AuthSession.saveAccessToken('owner-token'));
  tearDown(AuthSession.clear);

  Future<void> openScreen(WidgetTester tester, ApiClient api) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RentalIncomeScreen(
          getRentalIncomeUseCase: GetRentalIncomeUseCase(
            RentalManagementRepositoryImpl(
              remoteDataSource: RentalManagementRemoteDataSource(
                apiClient: api,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows confirmed cash and PromptPay receipts in the total', (
    tester,
  ) async {
    final api = _MockApiClient();
    when(() => api.get(path, headers: headers)).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {
          'total_satang': 35025,
          'transactions': [
            {
              'item_name': 'กล้อง',
              'confirmed_at': '2026-11-26T12:30:00Z',
              'payment_method': 'cash',
              'amount_satang': 15025,
            },
            {
              'item_name': 'ขาตั้ง',
              'confirmed_at': '2026-11-25T10:00:00Z',
              'payment_method': 'promptpay',
              'amount_satang': 20000,
            },
          ],
        },
      ),
    );

    await openScreen(tester, api);
    expect(find.text('฿ 350.25'), findsOneWidget);
    expect(find.text('กล้อง'), findsOneWidget);
    expect(find.text('ขาตั้ง'), findsOneWidget);
    expect(find.textContaining('เงินสด'), findsOneWidget);
    expect(find.textContaining('PromptPay'), findsOneWidget);
    expect(find.text('+฿150.25'), findsOneWidget);
  });

  testWidgets('shows history skeleton instead of a spinner while loading', (
    tester,
  ) async {
    final api = _MockApiClient();
    final response = Completer<ApiResponse>();
    when(
      () => api.get(path, headers: headers),
    ).thenAnswer((_) => response.future);

    await tester.pumpWidget(
      MaterialApp(
        home: RentalIncomeScreen(
          getRentalIncomeUseCase: GetRentalIncomeUseCase(
            RentalManagementRepositoryImpl(
              remoteDataSource: RentalManagementRemoteDataSource(
                apiClient: api,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('ประวัติการรับเงิน'), findsOneWidget);
    expect(find.byType(RentalIncomeTransactionSkeleton), findsWidgets);
    expect(find.text('฿ 0.00'), findsNothing);

    response.complete(
      const ApiResponse(
        statusCode: 200,
        data: {'total_satang': 0, 'transactions': []},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RentalIncomeTransactionSkeleton), findsNothing);
    expect(find.text('฿ 0.00'), findsOneWidget);
  });

  testWidgets('shows a zero total when there are no confirmed receipts', (
    tester,
  ) async {
    final api = _MockApiClient();
    when(() => api.get(path, headers: headers)).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'total_satang': 0, 'transactions': []},
      ),
    );

    await openScreen(tester, api);
    expect(find.text('฿ 0.00'), findsOneWidget);
    expect(find.text('ยังไม่มีรายการยืนยันรับเงิน'), findsOneWidget);
  });
}
