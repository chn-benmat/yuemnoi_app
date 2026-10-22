import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/location_service.dart';
import 'package:frontend/core/services/phone_call_service.dart';
import 'package:frontend/features/profile/data/datasources/rental_contact_remote_data_source.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

Position position(double latitude) => Position(
  latitude: latitude,
  longitude: 100.43,
  timestamp: DateTime(2026, 10, 17),
  accuracy: 3,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeLocationService extends LocationService {
  final updates = StreamController<Position>.broadcast();
  final freshGps = Completer<Position?>();
  int routeCalls = 0;
  bool slowGps = false;
  bool delayRoute = false;
  final pendingRoute = Completer<DrivingRouteResult?>();
  DrivingRouteResult? cached;
  @override
  DrivingRouteResult? cachedDrivingRoute(LatLng start, LatLng destination) =>
      cached;
  @override
  Future<Position?> getCurrentPosition() async =>
      slowGps ? freshGps.future : position(13.70);
  @override
  Future<Position?> getLastKnownPosition() async => position(13.70);
  @override
  Stream<Position> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 3,
  }) => updates.stream;
  @override
  Future<DrivingRouteResult?> fetchDrivingRoute(
    LatLng start,
    LatLng destination,
  ) async {
    routeCalls++;
    if (delayRoute) return pendingRoute.future;
    return DrivingRouteResult(
      points: [start, destination],
      distanceMeters: 2000,
      durationSeconds: 300,
    );
  }
}

class ContactSource extends RentalContactRemoteDataSource {
  int? requestedBooking;
  @override
  Future<String> getPhone({int? bookingId, String? conversationId}) async {
    requestedBooking = bookingId;
    return '+66987654321';
  }
}

class RecordingPhoneCall implements PhoneCallService {
  final numbers = <String>[];
  @override
  Future<bool> call(String phoneNumber) async {
    numbers.add(phoneNumber);
    return true;
  }
}

void main() {
  for (final isOwner in [false, true]) {
    testWidgets('calls actual partner phone when isOwner=$isOwner', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final location = FakeLocationService();
      addTearDown(location.updates.close);
      final contact = ContactSource();
      final phone = RecordingPhoneCall();
      await tester.pumpWidget(
        MaterialApp(
          home: RentalTrackingMapPage(
            locationService: location,
            contactDataSource: contact,
            phoneCallService: phone,
            bookingId: 25,
            isOwner: isOwner,
            ownerPhone: '0812345678',
            destinationLat: 13.71,
            destinationLng: 100.43,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(isOwner ? 'โทรหาผู้เช่า' : 'โทรหาเจ้าของ'));
      await tester.pump();
      expect(contact.requestedBooking, 25);
      expect(phone.numbers, ['+66987654321']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('missing contact never uses a sample phone number', (
    tester,
  ) async {
    final service = FakeLocationService();
    addTearDown(service.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RentalTrackingMapPage(
          locationService: service,
          isOwner: false,
          destinationLat: 13.71,
          destinationLng: 100.43,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('โทรหาเจ้าของ'));
    await tester.pump();
    expect(find.text('ไม่พบข้อมูลติดต่อของรายการเช่านี้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  Future<void> open(WidgetTester tester, FakeLocationService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RentalTrackingMapPage(
          locationService: service,
          destinationLat: 13.7115884,
          destinationLng: 100.4341077,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'route starts from last known location before a slow fresh GPS fix',
    (tester) async {
      final service = FakeLocationService()..slowGps = true;
      addTearDown(service.updates.close);
      await open(tester, service);
      expect(service.routeCalls, 1);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      service.freshGps.complete(position(13.70));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'moving updates the marker but route refresh waits three minutes and stops when hidden',
    (tester) async {
      final service = FakeLocationService();
      addTearDown(service.updates.close);
      await open(tester, service);
      expect(service.routeCalls, 1);
      service.updates.add(position(13.701));
      await tester.pump();
      expect(service.routeCalls, 1);
      await tester.pump(const Duration(minutes: 3));
      await tester.pump();
      expect(service.routeCalls, 2);
      await tester.pump(const Duration(minutes: 3));
      expect(service.routeCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 3));
      expect(service.routeCalls, 2);
    },
  );

  testWidgets('cached route stays visible while a fresh route is pending', (
    tester,
  ) async {
    final service = FakeLocationService()
      ..delayRoute = true
      ..cached = const DrivingRouteResult(
        points: [LatLng(13.70, 100.43), LatLng(13.7115884, 100.4341077)],
        distanceMeters: 2000,
        durationSeconds: 300,
      );
    addTearDown(service.updates.close);
    await open(tester, service);
    expect(find.text('2.0 กม.'), findsWidgets);
    expect(service.routeCalls, 1);
    service.pendingRoute.complete(service.cached);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covered route and background app do not refresh', (
    tester,
  ) async {
    final service = FakeLocationService();
    addTearDown(service.updates.close);
    await open(tester, service);
    final context = tester.element(find.byType(RentalTrackingMapPage));
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('covered'))),
    );
    await tester.pump(const Duration(seconds: 1));
    service.updates.add(position(13.701));
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(service.routeCalls, 1);
    Navigator.of(context).pop();
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(service.routeCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();
    expect(service.routeCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
