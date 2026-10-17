import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/location_service.dart';
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
