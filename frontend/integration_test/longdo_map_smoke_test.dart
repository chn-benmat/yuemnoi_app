import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/config/app_config.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/widgets/longdo_map_view.dart';
import 'package:frontend/core/widgets/pickup_location_field.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_handover_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('return map fills the gap and uses the return map styling', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env.local');
    final previousGeolocator = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FixedGeolocator(
      const LatLng(13.7443, 100.5298),
      waitForGps: Future<void>.value(),
    );
    addTearDown(() => GeolocatorPlatform.instance = previousGeolocator);

    await tester.pumpWidget(
      const MaterialApp(
        home: RentalHandoverPage(
          returnPoint: PickupLocation(
            name: 'สยามพารากอน',
            address: 'ถนนพระราม 1',
            latitude: 13.7463,
            longitude: 100.5349,
          ),
          returnDetails: SizedBox(height: 120),
        ),
      ),
    );

    final routeOverview = find.byTooltip('ดูภาพรวมเส้นทาง');
    await _waitFor(tester, () => routeOverview.evaluate().isNotEmpty);
    final titleBar = find
        .ancestor(
          of: find.text('เส้นทางคืนสินค้า'),
          matching: find.byType(Container),
        )
        .first;
    final webView = find.byType(WebViewWidget);
    final controller = tester
        .widget<WebViewWidget>(webView)
        .platform
        .params
        .controller;
    expect(
      (
        gap: tester.getTopLeft(webView).dy - tester.getBottomLeft(titleBar).dy,
        hasLeftControls: await controller.runJavaScriptReturningResult(
          'map.Ui.Zoombar.visible() || map.Ui.Terrain.visible()',
        ),
      ),
      (gap: 0.0, hasLeftControls: false),
    );
    await _expectThaiMapLabels(tester);

    final distance = find.byIcon(Icons.directions_car_rounded);
    await _waitFor(tester, () => distance.evaluate().isNotEmpty);
    expect(
      await controller.runJavaScriptReturningResult('''
        (() => {
          const pins = map.Route.list();
          return pins.length === 2 && pins.every(pin => pin.toJSON().properties.draggable === false);
        })()
      '''),
      isTrue,
      reason: 'Both route pins have dragging disabled after calculation',
    );
    expect(
      await controller.runJavaScriptReturningResult('''
        (() => {
          const button = document.querySelector('.maplibregl-ctrl-attrib-button');
          const credits = document.querySelector('.maplibregl-ctrl-attrib-inner');
          return button?.getClientRects().length > 0 && credits?.getClientRects().length === 0;
        })()
      '''),
      isTrue,
    );
    await controller.runJavaScript(
      "document.querySelector('.maplibregl-ctrl-attrib-button').click()",
    );
    expect(
      await controller.runJavaScriptReturningResult('''
        (() => {
          const credits = document.querySelector('.maplibregl-ctrl-attrib-inner');
          return credits?.getClientRects().length > 0 && credits.innerText.includes('Longdo Map');
        })()
      '''),
      isTrue,
    );
  }, skip: !const bool.fromEnvironment('VERIFY_LIVE_LONGDO'));

  testWidgets('loads the Longdo map and finds a Bangkok landmark', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env.local');
    expect(AppConfig.longdoMapApiKey, isNotEmpty);
    final map = GlobalKey<LongdoMapViewState>();
    final ready = Completer<bool>();
    const destination = LatLng(13.7463, 100.5349);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LongdoMapView(
            key: map,
            point: destination,
            onReady: (result) {
              if (!ready.isCompleted) ready.complete(result);
            },
          ),
        ),
      ),
    );
    await _waitFor(tester, () => ready.isCompleted);
    expect(await ready.future, isTrue);

    final results = await map.currentState!.search('สยามพารากอน');
    expect(results, isNotEmpty);
    expect(results.first.hasCoordinates, isTrue);

    final pinAddress = await map.currentState!.addressAt(destination);
    expect(pinAddress?.name, 'สยามพารากอน');
    expect(pinAddress?.address, contains('เขตปทุมวัน'));

    final distance = await map.currentState!.showRoute(
      const LatLng(13.7443, 100.5298),
      destination,
    );
    expect(distance, isNotEmpty);
  }, skip: !const bool.fromEnvironment('VERIFY_LIVE_LONGDO'));

  testWidgets('opens the pickup map from the form and accepts a search immediately', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env.local');
    final previousGeolocator = GeolocatorPlatform.instance;
    final geolocator = _FixedGeolocator(
      const LatLng(0, 0),
      waitForGps: Future<void>.value(),
      permission: LocationPermission.denied,
    );
    GeolocatorPlatform.instance = geolocator;
    addTearDown(() => GeolocatorPlatform.instance = previousGeolocator);
    String? selectedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupLocationField(
            onChanged: (place) => selectedName = place.name,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pickup-location-field')));
    final search = find.byKey(const ValueKey('pickup-location-search'));
    await _waitFor(tester, () => search.evaluate().isNotEmpty);
    expect(tester.widget<TextField>(search).enabled, isNot(false));

    final map = find.byType(LongdoMapView);
    await _waitFor(tester, () => map.evaluate().isNotEmpty);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byKey(const Key('pickup-coordinates')), findsNothing);
    expect(geolocator.reads, 0);
    expect(tester.widget<LongdoMapView>(map).point, isNull);
    expect(
      find.descendant(
        of: map,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    final confirmation = find.byKey(
      const ValueKey('confirm-location-picker-button'),
    );
    expect(
      tester.getBottomLeft(search).dy,
      lessThan(tester.getTopLeft(map).dy),
    );
    expect(
      tester.getSize(map).height,
      greaterThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio * 0.40,
      ),
    );
    expect(
      tester.getBottomLeft(map).dy,
      lessThan(tester.getTopLeft(confirmation).dy),
    );

    await tester.enterText(search, 'สยามพารากอน');
    final result = find.descendant(
      of: find.byType(ListTile),
      matching: find.textContaining('สยามพารากอน'),
    );
    await _waitFor(tester, () => result.evaluate().isNotEmpty);
    await _expectPickupScaleAndLabels(tester);
    final webView = tester.widget<WebViewWidget>(find.byType(WebViewWidget));
    final controller = webView.platform.params.controller;
    expect(
      await controller.runJavaScriptReturningResult(
        '!map.Ui.Zoombar.visible() && !map.Ui.Terrain.visible() && map.Ui.Crosshair.visible()',
      ),
      isTrue,
    );
    expect(
      await controller.runJavaScriptReturningResult(
        "document.querySelector('.maplibregl-ctrl-attrib.maplibregl-compact:not(.maplibregl-compact-show) .maplibregl-ctrl-attrib-button')?.getClientRects().length > 0",
      ),
      isTrue,
    );
    const toggleCredits =
        "document.querySelector('.maplibregl-ctrl-attrib-button').click()";
    await controller.runJavaScript(toggleCredits);
    expect(
      await controller.runJavaScriptReturningResult(
        "(() => { const text = document.querySelector('.maplibregl-ctrl-attrib.maplibregl-compact-show')?.innerText ?? ''; return text.includes('Longdo Map') && text.includes('Terms'); })()",
      ),
      isTrue,
    );
    await controller.runJavaScript(toggleCredits);
    await tester.tap(result.first);
    await tester.pump();
    final name = find.byKey(const Key('pickup-name'));
    expect(
      tester.widget<TextFormField>(name).controller?.text,
      contains('สยามพารากอน'),
    );
    await tester.tap(confirmation);
    await _waitFor(tester, () => selectedName != null);
    expect(selectedName, contains('สยามพารากอน'));
  }, skip: !const bool.fromEnvironment('VERIFY_LIVE_LONGDO'));

  testWidgets(
    'starts at the device position and confirms its Longdo place without typing',
    (tester) async {
      await dotenv.load(fileName: '.env.local');
      const point = LatLng(13.7463, 100.5349);
      final previousGeolocator = GeolocatorPlatform.instance;
      final releaseGps = Completer<void>();
      final geolocator = _FixedGeolocator(point, waitForGps: releaseGps.future);
      GeolocatorPlatform.instance = geolocator;
      addTearDown(() {
        if (!releaseGps.isCompleted) releaseGps.complete();
        GeolocatorPlatform.instance = previousGeolocator;
      });

      PickupLocation? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PickupLocationField(onChanged: (place) => selected = place),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(geolocator.reads, 1, reason: 'Read GPS before opening the picker');
      await tester.tap(find.byKey(const Key('pickup-location-field')));

      final map = find.byType(LongdoMapView);
      final search = find.byKey(const ValueKey('pickup-location-search'));
      final name = find.byKey(const Key('pickup-name'));
      await _waitFor(tester, () => name.evaluate().isNotEmpty);
      await _waitFor(tester, () => geolocator.reads == 1);
      expect(map, findsNothing, reason: 'No default map while GPS is pending');
      await tester.enterText(search, 'ก');
      releaseGps.complete();
      await _waitFor(tester, () => map.evaluate().isNotEmpty);
      expect(tester.widget<LongdoMapView>(map).point, point);
      expect(tester.widget<TextField>(search).controller?.text, 'ก');
      await tester.enterText(search, '');
      FocusManager.instance.primaryFocus?.unfocus();
      await _waitFor(tester, () => name.evaluate().isNotEmpty);
      expect(
        tester.widget<TextFormField>(name).controller?.text,
        isEmpty,
        reason: 'Keep coordinates out of the name while looking up the pin',
      );
      expect(find.text('กำลังระบุสถานที่จากหมุด…'), findsOneWidget);
      final confirmation = find.byKey(
        const ValueKey('confirm-location-picker-button'),
      );
      expect(tester.widget<FilledButton>(confirmation).onPressed, isNull);
      await _waitFor(tester, () {
        return tester.widget<TextFormField>(name).controller?.text ==
            'สยามพารากอน';
      });
      expect(
        tester.widget<TextFormField>(name).controller?.text,
        'สยามพารากอน',
      );

      await tester.tap(confirmation);
      await _waitFor(tester, () => selected != null);
      expect(selected?.name, 'สยามพารากอน');
      expect(selected?.address, contains('เขตปทุมวัน'));
      expect(selected?.latitude, point.latitude);
      expect(selected?.longitude, point.longitude);
    },
    skip: !const bool.fromEnvironment('VERIFY_LIVE_LONGDO'),
  );

  testWidgets('prepares the Longdo map when scrolling toward the pickup field', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env.local');
    const point = LatLng(13.7463, 100.5349);
    final previousGeolocator = GeolocatorPlatform.instance;
    final geolocator = _FixedGeolocator(
      point,
      waitForGps: Future<void>.value(),
    );
    GeolocatorPlatform.instance = geolocator;
    addTearDown(() => GeolocatorPlatform.instance = previousGeolocator);

    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    PickupLocation? selected;
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              Column(
                children: [
                  SizedBox(height: viewportHeight * 3),
                  PickupLocationField(onChanged: (place) => selected = place),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(geolocator.reads, 0);
    scroll.jumpTo(viewportHeight * 2);
    await _waitFor(tester, () => geolocator.reads == 1);
    final warmed = Completer<bool>();
    unawaited(
      LongdoMapView.preloadPicker(Future.value(point)).then(warmed.complete),
    );
    await _waitFor(tester, () => warmed.isCompleted);
    expect(await warmed.future, isTrue);
    expect(find.byType(LongdoMapView), findsNothing);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pickup-location-field')));
    final map = find.byType(LongdoMapView);
    await _waitFor(tester, () => map.evaluate().isNotEmpty);
    expect(tester.widget<LongdoMapView>(map).point, point);
    expect(geolocator.reads, 1);
    final name = find.byKey(const Key('pickup-name'));
    await _waitFor(
      tester,
      () =>
          tester.widget<TextFormField>(name).controller?.text == 'สยามพารากอน',
    );
    final controller = tester
        .widget<WebViewWidget>(find.byType(WebViewWidget))
        .platform
        .params
        .controller;
    await _expectPickupScaleAndLabels(tester);
    expect(
      await controller.runJavaScriptReturningResult(
        "Boolean(document.querySelector('.maplibregl-ctrl-attrib.maplibregl-compact:not(.maplibregl-compact-show)'))",
      ),
      isTrue,
    );

    const unnamedPoint = LatLng(13.747, 100.535);
    await controller.runJavaScript('''
      addressAt = (_, requestId) => send('pin-address', { requestId, result: null });
      send('pick', { lat: ${unnamedPoint.latitude}, lon: ${unnamedPoint.longitude} });
    ''');
    await _waitFor(
      tester,
      () =>
          tester.widget<TextFormField>(name).controller?.text ==
          'จุดนัดรับที่ปักหมุด',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-location-picker-button')),
    );
    await _waitFor(tester, () => selected != null);
    expect(selected?.name, 'จุดนัดรับที่ปักหมุด');
    expect(selected?.latitude, unnamedPoint.latitude);
    expect(selected?.longitude, unnamedPoint.longitude);
  }, skip: !const bool.fromEnvironment('VERIFY_LIVE_LONGDO'));
}

Future<void> _expectPickupScaleAndLabels(WidgetTester tester) async {
  final controller = tester
      .widget<WebViewWidget>(find.byType(WebViewWidget))
      .platform
      .params
      .controller;
  expect(
    await controller.runJavaScriptReturningResult('map.zoom()'),
    closeTo(LongdoMapView.pickupZoom, 0.01),
  );
  expect(
    await controller.runJavaScriptReturningResult(
      r"document.querySelector('.maplibregl-ctrl-scale')?.textContent.trim().replace(/\s+/g, ' ') === '100 m'",
    ),
    isTrue,
  );
  await _expectThaiMapLabels(tester);
}

Future<void> _expectThaiMapLabels(WidgetTester tester) async {
  final controller = tester
      .widget<WebViewWidget>(find.byType(WebViewWidget))
      .platform
      .params
      .controller;
  expect(
    await controller.runJavaScriptReturningResult('''
      (() => {
        const expected = JSON.stringify(thaiMapNameLabel);
        const fields = map.Renderer.getStyle().layers
          .filter(layer => layer.type === 'symbol')
          .map(layer => layer.layout?.['text-field'])
          .filter(field => Array.isArray(field) && /"name_[le]"/.test(JSON.stringify(field)));
        return expected.includes('englishName') && fields.length > 0 &&
          fields.every(field => JSON.stringify(field) === expected);
      })()
    '''),
    isTrue,
  );
}

class _FixedGeolocator extends GeolocatorPlatform {
  _FixedGeolocator(
    this.point, {
    required this.waitForGps,
    this.permission = LocationPermission.whileInUse,
  });

  final LatLng point;
  final Future<void> waitForGps;
  final LocationPermission permission;
  int reads = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    await waitForGps;
    return Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime(2026),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 25));
  while (!condition() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue);
}
