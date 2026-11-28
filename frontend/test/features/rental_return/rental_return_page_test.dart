import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/rental_return/data/datasources/rental_return_remote_data_source.dart';
import 'package:frontend/features/rental_return/data/repositories/rental_return_repository_impl.dart';
import 'package:frontend/features/rental_return/presentation/pages/rental_return_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

const _confirmLabel = 'ยืนยันรับคืนสินค้า';
const _returnLocation = {
  'pickup_location': 'ซีคอน บางแค',
  'pickup_address': 'ถนนเพชรเกษม บางแค',
  'latitude': 13.7115884,
  'longitude': '100.4341077',
};

void main() {
  setUpAll(() => initializeDateFormatting('th'));
  for (final isLender in [false, true]) {
    testWidgets(
      '${isLender ? 'lender' : 'renter'} sees return details and the appropriate actions',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 700);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        var bookingStatus = 'active';
        await _showReturnPage(
          tester,
          isLender: isLender,
          bookingLocation: _returnLocation,
          bookingStatus: () => bookingStatus,
        );

        expect(find.text('คืนสินค้า'), findsOneWidget);
        expect(find.text('ถนนเพชรเกษม บางแค'), findsOneWidget);
        expect(find.text('ซีคอน บางแค'), findsOneWidget);
        expect(
          tester.getTopLeft(find.textContaining('กำหนดคืน')).dy,
          greaterThan(tester.getBottomLeft(find.text('คืนสินค้า')).dy),
        );
        expect(find.text('ชำระเงิน'), findsNothing);
        expect(find.text('ตรวจรับ & ชำระเงิน'), findsNothing);

        if (isLender) {
          final checkbox = find.byType(Checkbox);
          final confirm = find.widgetWithText(ElevatedButton, _confirmLabel);
          expect(checkbox.hitTestable(), findsOneWidget);
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
          await tester.tap(find.text('ได้รับสินค้าคืนและตรวจสภาพแล้ว'));
          await tester.pump();
          expect(tester.widget<Checkbox>(checkbox).value, isTrue);
          expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
        } else {
          expect(find.text('ส่งคืนสินค้า').hitTestable(), findsOneWidget);
          expect(find.text('นำสินค้าไปส่งที่จุดคืนตามนัด'), findsOneWidget);
          expect(find.byType(Checkbox), findsNothing);
          expect(find.text(_confirmLabel), findsNothing);

          bookingStatus = 'return_ready';
          await tester.pump(const Duration(seconds: 10));
          await tester.pump();
          expect(find.text('รอร้านค้ายืนยันรับสินค้าคืน'), findsOneWidget);
          expect(find.text('นำสินค้าไปส่งที่จุดคืนตามนัด'), findsNothing);
        }
      },
    );
  }

  testWidgets(
    'a legacy booking uses the listing address for the same location',
    (tester) async {
      await _showReturnPage(
        tester,
        bookingLocation: {'pickup_location': 'สยามพารากอน'},
      );

      expect(find.text('ถนนพระราม 1'), findsOneWidget);
    },
  );

  testWidgets(
    'unusable GPS coordinates leave the saved return location visible',
    (tester) async {
      await _showReturnPage(
        tester,
        bookingLocation: {
          'pickup_location': 'ซีคอน บางแค',
          'latitude': 13.7115884,
          'longitude': 'NaN',
        },
      );

      expect(find.text('คืนสินค้า'), findsOneWidget);
      expect(find.text('ซีคอน บางแค'), findsOneWidget);
    },
  );

  testWidgets(
    'the inspection stays reachable with large text on a short screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 440);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await _showReturnPage(
        tester,
        isLender: true,
        bookingLocation: _returnLocation,
        textScaler: TextScaler.linear(2),
      );

      final checkbox = find.byType(Checkbox);
      await tester.ensureVisible(checkbox);
      await tester.pump();
      expect(checkbox.hitTestable(), findsOneWidget);
      await tester.tap(checkbox);
      await tester.pump();

      final confirm = find.widgetWithText(ElevatedButton, _confirmLabel);
      await tester.ensureVisible(confirm);
      await tester.pump();
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the completion dialog opens when the completed status arrives', (
    tester,
  ) async {
    var status = 'active';
    await _showReturnPage(
      tester,
      isLender: true,
      bookingLocation: _returnLocation,
      bookingStatus: () => status,
    );

    status = 'completed';
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsOneWidget);
  });
}

Future<void> _showReturnPage(
  WidgetTester tester, {
  bool isLender = false,
  required Map<String, Object> bookingLocation,
  String Function()? bookingStatus,
  TextScaler? textScaler,
}) async {
  final api = _Api();
  final now = DateTime.now().toUtc();
  when(
    () => api.get(
      '/api/rentals/73/return-session',
      headers: any(named: 'headers'),
    ),
  ).thenAnswer(
    (_) async => ApiResponse(
      statusCode: 200,
      data: {
        'booking': {
          'id': 73,
          'item_id': 17,
          'user_id': 'renter',
          'status': bookingStatus?.call() ?? 'active',
          'start_at': now.subtract(const Duration(days: 1)).toIso8601String(),
          'end_at': now.add(const Duration(days: 1)).toIso8601String(),
          'total_price': 100,
          ...bookingLocation,
        },
        'item': {
          'id': 17,
          'item_name': 'Camera',
          'pickup_location': 'สยามพารากอน',
          'pickup_address': 'ถนนพระราม 1',
          'pickup_latitude': 13.746,
          'pickup_longitude': 100.5349,
        },
        'owner_id': 'owner',
        'owner_name': 'Owner',
        'renter_name': 'Renter',
        'return_state': <String, Object>{},
      },
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      home: RentalReturnPage(
        rentalId: 73,
        isLender: isLender,
        repository: RentalReturnRepositoryImpl(
          remoteDataSource: RentalReturnRemoteDataSource(
            apiClient: api,
            accessToken: () => 'session-token',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}
