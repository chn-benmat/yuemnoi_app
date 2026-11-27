import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/services/location_service.dart';
import 'package:frontend/core/services/phone_call_service.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/profile/data/datasources/rental_contact_remote_data_source.dart';
import 'package:frontend/features/profile/domain/entities/rental_handover_payment.dart';
import 'package:frontend/features/profile/domain/usecases/update_booking_status_usecase.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
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
  ChatConversation? conversation;

  @override
  Future<ChatConversation?> getConversation({
    int? bookingId,
    String? conversationId,
  }) async {
    requestedBooking = bookingId;
    return conversation;
  }

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

class HandoverStatus extends Fake implements UpdateBookingStatusUseCase {
  bool active = false;

  @override
  Future<RentalHandoverPayment> handoverPayment({
    required int bookingId,
    bool confirm = false,
    String? promptPayPhone,
    String? promptPayNationalId,
  }) async {
    if (confirm) active = true;
    return RentalHandoverPayment(
      status: active ? 'active' : 'confirmed',
      paymentMethod: 'cash',
      paymentConfirmed: active,
      totalSatang: 150000,
    );
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

  for (final (description, isOwner, openPayment) in [
    ('lender confirming receipt', true, true),
    ('renter in the payment sheet', false, true),
    ('renter on the pickup map', false, false),
  ]) {
    testWidgets('$description returns to the original chat', (tester) async {
      const bookingId = 25;
      SharedPreferences.setMockInitialValues({
        'handover_progress_step_booking_$bookingId': 1,
      });
      final service = FakeLocationService();
      addTearDown(service.updates.close);
      final handover = HandoverStatus();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RentalTrackingMapPage(
                      bookingId: bookingId,
                      isOwner: isOwner,
                      startDate: DateTime(2020),
                      destinationLat: 13.71,
                      destinationLng: 100.43,
                      locationService: service,
                      returnToPreviousChat: true,
                      updateBookingStatusUseCase: handover,
                    ),
                  ),
                ),
                child: const Text('Open pickup from chat'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open pickup from chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      if (openPayment) {
        await tester.tap(
          find.text(isOwner ? 'ยืนยันการรับเงิน' : 'ดูสถานะนัดรับ'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      if (isOwner) {
        final button = find.text('ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿1500]');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.widgetWithText(ElevatedButton, 'ยืนยัน'));
      } else {
        handover.active = true;
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RentalTrackingMapPage), findsNothing);
      expect(find.text('Open pickup from chat').hitTestable(), findsOneWidget);
    });
  }

  testWidgets('payment from rental status opens the associated chat', (
    tester,
  ) async {
    final service = FakeLocationService();
    addTearDown(service.updates.close);
    final handover = HandoverStatus();
    final contact = ContactSource()
      ..conversation = const ChatConversation(
        id: 'rental-conversation',
        otherUserId: 'lender',
        name: 'Lender',
        role: ChatParticipantRole.owner,
        avatarAsset: '',
        preview: '',
        timeLabel: '',
      );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RentalTrackingMapPage(
                    bookingId: 27,
                    startDate: DateTime(2020),
                    destinationLat: 13.71,
                    destinationLng: 100.43,
                    locationService: service,
                    contactDataSource: contact,
                    updateBookingStatusUseCase: handover,
                  ),
                ),
              ),
              child: const Text('Open pickup from rental status'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.chatDetail,
          builder: (_, state) =>
              Scaffold(body: Text((state.extra as ChatConversation).id)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open pickup from rental status'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    handover.active = true;
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(contact.requestedBooking, 27);
    expect(find.text('rental-conversation').hitTestable(), findsOneWidget);
    expect(
      find.byType(RentalTrackingMapPage, skipOffstage: false),
      findsNothing,
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open pickup from rental status'), findsOneWidget);
  });

  testWidgets('resuming pickup without a known payment method shows status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'handover_progress_step_booking_930': 1,
    });
    final service = FakeLocationService();
    addTearDown(service.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RentalTrackingMapPage(
          locationService: service,
          bookingId: 930,
          isOwner: false,
          destinationLat: 13.71,
          destinationLng: 100.43,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ดูสถานะนัดรับ'), findsOneWidget);
    expect(find.text('ชำระเงิน'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ไม่พบข้อมูลติดต่อของรายการเช่านี้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final bookingId in <int?>[null, 25]) {
    testWidgets(
      'does not load a route before the map can open (ID: $bookingId)',
      (tester) async {
        final service = FakeLocationService();
        addTearDown(service.updates.close);
        await tester.pumpWidget(
          MaterialApp(
            home: RentalTrackingMapPage(
              requireBookingId: true,
              bookingId: bookingId,
              destinationLat: 13.71,
              destinationLng: 100.43,
              locationService: service,
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text(
            bookingId == null
                ? 'ไม่พบรายการเช่านี้ กรุณาเปิดหน้าจากรายการเช่าของคุณ'
                : 'กรุณาเข้าสู่ระบบเพื่อดูรายละเอียดนัดรับ',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(service.routeCalls, 0);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
