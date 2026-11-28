import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:frontend/core/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/presentation/pages/location_picker_map_page.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  testWidgets(
    'pasting coordinates keeps the exact pin even when an earlier GPS lookup completes',
    (tester) async {
      final service = _SearchService();
      await tester.pumpWidget(
        MaterialApp(home: LocationPickerMapPage(locationService: service)),
      );
      final search = find.descendant(
        of: find.byKey(const ValueKey('pickup-location-search')),
        matching: find.byType(TextField),
      );
      await tester.tap(find.byTooltip('ตำแหน่งปัจจุบันของคุณ'));
      await tester.tap(search);
      await tester.enterText(
        search,
        'https://www.google.com/maps/search/?api=1&query=13.7467785%2C100.534954',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(service.suggestionQueries, isEmpty);
      expect(service.queries, isEmpty);
      await tester.tap(find.text('ปักหมุดตามพิกัด'));
      service.currentPosition.complete(
        Position(
          latitude: 13.71,
          longitude: 100.43,
          timestamp: DateTime(2026),
          accuracy: 2,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center.latitude, 13.7467785);
      expect(map.mapController!.camera.center.longitude, 100.534954);
      await tester.pumpAndSettle();
      final tip = tester.getRect(
        find.byKey(const ValueKey('pickup-map-pin-tip')),
      );
      expect(tip.bottom, tester.getCenter(find.byType(FlutterMap)).dy);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Thai meeting point title is shown while keeping the upstream name separate',
    (tester) async {
      final service = _SearchService();
      await tester.pumpWidget(
        MaterialApp(home: LocationPickerMapPage(locationService: service)),
      );
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
      );
      await tester.tap(search);
      await tester.enterText(search, 'Consulate');
      await tester.pump(const Duration(milliseconds: 600));
      service.suggestions.single.complete([
        const LocationSearchResult(
          name: 'จุดนัดรับบริเวณซอยพร้อมมิตร',
          originalName: 'Honorary Consulate of Albania',
          displayName: 'จุดนัดรับบริเวณซอยพร้อมมิตร, กรุงเทพมหานคร',
          latitude: 13.7336306,
          longitude: 100.5720061,
        ),
      ]);
      await tester.pump();
      await tester.tap(find.text('จุดนัดรับบริเวณซอยพร้อมมิตร'));
      await tester.pump();
      expect(find.text('จุดนัดรับบริเวณซอยพร้อมมิตร'), findsOneWidget);
      expect(
        find.text('ชื่อเดิม: Honorary Consulate of Albania'),
        findsOneWidget,
      );
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final tiles = map.children.whereType<TileLayer>().single;
      expect(tiles.urlTemplate, contains('hl=th'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'street fallback is labeled and asks the user to refine the house pin',
    (tester) async {
      final service = _SearchService();
      await tester.pumpWidget(
        MaterialApp(home: LocationPickerMapPage(locationService: service)),
      );
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
      );
      await tester.tap(search);
      await tester.enterText(search, '719/259 พุดตาน');
      await tester.pump(const Duration(milliseconds: 600));
      service.suggestions.single.complete([
        const LocationSearchResult(
          name: 'ถนนพุดตานใน',
          displayName: 'ถนนพุดตานใน, ดุสิต, กรุงเทพมหานคร',
          latitude: 13.772,
          longitude: 100.513,
          isApproximate: true,
        ),
      ]);
      await tester.pump();
      expect(
        find.textContaining('ถนน/พื้นที่ (ยังไม่พบเลขบ้าน)'),
        findsOneWidget,
      );
      expect(find.text('ค้นหาใน Google Maps'), findsOneWidget);
      await tester.tap(find.text('ถนนพุดตานใน'));
      await tester.pump();
      expect(
        find.text('ยังไม่พบเลขบ้าน กรุณาเลื่อนหมุดไปจุดนัดรับที่ต้องการ'),
        findsOneWidget,
      );
      expect(
        find.text('719/259 พุดตาน'),
        findsNothing,
        reason: 'Do not label a street coordinate as the searched house.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('typing suggests real places without arrow or refresh buttons', (
    tester,
  ) async {
    final service = _SearchService();
    await tester.pumpWidget(
      MaterialApp(home: LocationPickerMapPage(locationService: service)),
    );
    final search = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
    );
    await tester.tap(search);
    await tester.enterText(search, 'สวน');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(search, 'สวนเบญ');
    await tester.pump(const Duration(milliseconds: 600));
    expect(service.suggestionQueries, ['สวนเบญ']);
    expect(
      service.queries,
      isEmpty,
      reason: 'Autocomplete must not use Nominatim.',
    );
    service.suggestions.single.complete([_park]);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text(_park.name),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await tester.enterText(search, 'another');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(search, 'latest');
    await tester.pump(const Duration(milliseconds: 600));
    service.suggestions[2].complete([]);
    await tester.pump();
    service.suggestions[1].complete([_park]);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text(_park.name),
      ),
      findsNothing,
    );
    await tester.enterText(search, 'clear before debounce');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'submit searches real places and selecting preserves the returned map pin',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final service = _SearchService();
      await tester.pumpWidget(
        MaterialApp(home: LocationPickerMapPage(locationService: service)),
      );
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
      );
      await tester.tap(search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.enterText(search, 'สวนเบญจกิติ');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        service.queries,
        isEmpty,
        reason: 'Wait for the debounce before requesting suggestions.',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(service.queries, ['สวนเบญจกิติ']);
      service.pending.single.complete([_park]);
      await tester.pump();
      final resultTitle = find.descendant(
        of: find.byType(ListTile),
        matching: find.text(_park.name),
      );
      expect(resultTitle, findsOneWidget);
      final controller = tester.widget<TextField>(search).controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(
        resultTitle,
        findsOneWidget,
        reason: 'Moving the cursor must not clear real search results.',
      );
      expect(tester.getRect(resultTitle).bottom, lessThan(844 - 320));
      expect(
        find.byKey(const ValueKey('confirm-location-picker-button')),
        findsNothing,
      );
      await tester.tap(resultTitle);
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center.latitude, _park.latitude);
      expect(map.mapController!.camera.center.longitude, _park.longitude);
      expect(find.text(_park.displayName), findsOneWidget);
      expect(
        find.byKey(const ValueKey('confirm-location-picker-button')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(_park.displayName),
        findsOneWidget,
        reason:
            'Reverse geocoding must not overwrite a selected search result.',
      );
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_park.displayName), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('search shows empty/error states and ignores stale results', (
    tester,
  ) async {
    final service = _SearchService();
    await tester.pumpWidget(
      MaterialApp(home: LocationPickerMapPage(locationService: service)),
    );
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
    );
    await tester.tap(search);
    await tester.enterText(search, 'old query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.enterText(search, 'new query');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    service.pending[1].complete([]);
    await tester.pump();
    expect(find.textContaining('ไม่พบสถานที่'), findsOneWidget);
    service.pending[0].complete([_park]);
    await tester.pump();
    expect(find.text(_park.name), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    service.pending[2].completeError(StateError('offline'));
    await tester.pump();
    expect(find.textContaining('ค้นหาสถานที่ไม่ได้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('one tap on pickup search immediately shows the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LocationPickerMapPage()));
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
    );
    await tester.tap(search);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'one tap opens the keyboard and keeps the blinking cursor after keyboard resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(const MaterialApp(home: LocationPickerMapPage()));
      await tester.pump(const Duration(milliseconds: 500));
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
      );
      final editable = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );

      await tester.tap(search);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isTrue,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('confirm-location-picker-button')),
        findsNothing,
        reason: 'The confirmation panel must be hidden while searching.',
      );
      expect(
        tester.widget<EditableText>(editable).focusNode.hasFocus,
        isTrue,
        reason:
            'Opening the keyboard must not remove focus from the search field.',
      );
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<EditableTextState>(editable).cursorCurrentlyVisible,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

const _park = LocationSearchResult(
  name: 'สวนเบญจกิติ',
  displayName: 'สวนเบญจกิติ, เขตคลองเตย, กรุงเทพมหานคร',
  latitude: 13.7292243,
  longitude: 100.5585211,
);

class _SearchService extends LocationService {
  final currentPosition = Completer<Position?>();

  @override
  Future<Position?> getCurrentPosition() => currentPosition.future;

  final suggestionQueries = <String>[];
  final suggestions = <Completer<List<LocationSearchResult>>>[];
  @override
  Future<List<LocationSearchResult>> suggestLocations(String query) {
    suggestionQueries.add(query);
    final result = Completer<List<LocationSearchResult>>();
    suggestions.add(result);
    return result.future;
  }

  final queries = <String>[];
  final pending = <Completer<List<LocationSearchResult>>>[];
  @override
  Future<List<LocationSearchResult>> searchLocations(String query) {
    queries.add(query);
    final result = Completer<List<LocationSearchResult>>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(double lat, double lon) async =>
      null;
}
