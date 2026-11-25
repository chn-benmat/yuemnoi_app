import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/rental_return/data/datasources/rental_return_remote_data_source.dart';
import 'package:frontend/features/rental_return/data/repositories/rental_return_repository_impl.dart';
import 'package:frontend/features/rental_return/presentation/pages/rental_return_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

const _initialPosition = LatLng(13.753, 100.481);
const _returnPoint = LatLng(13.7115884, 100.4341077);
const _navigationTooltip = 'นำทางด้วย Google Maps';
const _confirmLabel = 'ยืนยันรับคืนสินค้า';
const _returnLocation = {
  'pickup_location': 'ซีคอน บางแค',
  'pickup_note': 'หน้าทางเข้าชั้น G',
  'latitude': 13.7115884,
  'longitude': '100.4341077',
};

class _DeviceLocation extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast();

  Position toPosition(LatLng point) => Position(
    latitude: point.latitude,
    longitude: point.longitude,
    timestamp: DateTime(2026, 11, 25),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => toPosition(_initialPosition);

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => toPosition(_initialPosition);

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positions.stream;
}

void main() {
  setUpAll(() => initializeDateFormatting('th'));
  late _DeviceLocation location;
  setUp(() {
    final original = GeolocatorPlatform.instance;
    location = _DeviceLocation();
    GeolocatorPlatform.instance = location;
    addTearDown(() async {
      GeolocatorPlatform.instance = original;
      await location.positions.close();
    });
  });

  for (final isLender in [false, true]) {
    testWidgets(
      '${isLender ? 'lender' : 'renter'} sees both pins as soon as the return page opens',
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

        expect(find.text('เส้นทางคืนสินค้า'), findsOneWidget);
        expect(find.text('หน้าทางเข้าชั้น G'), findsOneWidget);
        expect(find.byTooltip(_navigationTooltip), findsOneWidget);
        expect(find.byType(FlutterMap), findsOneWidget);
        final mapBounds = tester.getRect(find.byType(FlutterMap));
        expect(mapBounds.left, 0);
        expect(mapBounds.width, 390);
        expect(
          mapBounds.contains(tester.getCenter(find.text('เส้นทางคืนสินค้า'))),
          isTrue,
        );
        expect(
          tester.getTopLeft(find.textContaining('กำหนดคืน')).dy,
          greaterThan(mapBounds.bottom),
        );
        expect(find.text('ตัวคุณ'), findsOneWidget);
        expect(find.text('ซีคอน บางแค'), findsWidgets);
        expect(_pins(tester), containsAll([_initialPosition, _returnPoint]));
        final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
        expect(
          map.mapController!.camera.visibleBounds.contains(_initialPosition),
          isTrue,
        );
        expect(
          map.mapController!.camera.visibleBounds.contains(_returnPoint),
          isTrue,
        );
        expect(find.text('ชำระเงิน'), findsNothing);
        expect(find.text('ตรวจรับ & ชำระเงิน'), findsNothing);

        const moved = LatLng(13.754, 100.482);
        location.positions.add(location.toPosition(moved));
        await tester.pump();
        expect(_pins(tester), containsAll([moved, _returnPoint]));
        expect(_pins(tester), isNot(contains(_initialPosition)));

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
          expect(_pins(tester), containsAll([moved, _returnPoint]));
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
          expect(_pins(tester), containsAll([moved, _returnPoint]));
        }
      },
    );
  }

  testWidgets('a legacy booking uses the listing pin for the same location', (
    tester,
  ) async {
    await _showReturnPage(
      tester,
      bookingLocation: {'pickup_location': 'สยามพารากอน'},
    );

    expect(_pins(tester), contains(const LatLng(13.746, 100.5349)));
  });

  testWidgets('an unusable pin leaves the saved return location visible', (
    tester,
  ) async {
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
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byTooltip(_navigationTooltip), findsNothing);
  });

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

  testWidgets('the return map closes when the completed status arrives', (
    tester,
  ) async {
    var status = 'active';
    await _showReturnPage(
      tester,
      isLender: true,
      bookingLocation: _returnLocation,
      bookingStatus: () => status,
    );
    expect(find.byType(FlutterMap), findsOneWidget);

    status = 'completed';
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('คืนอุปกรณ์สำเร็จ!'), findsOneWidget);
    expect(find.byType(FlutterMap, skipOffstage: false), findsNothing);
  });
}

Iterable<LatLng> _pins(WidgetTester tester) => tester
    .widget<MarkerLayer>(find.byType(MarkerLayer))
    .markers
    .map((marker) => marker.point);

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
