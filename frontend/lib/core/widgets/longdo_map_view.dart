import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../models/pickup_location.dart';
import '../services/longdo_map_data.dart';

Map<String, double> _coordinates(LatLng point) => {
  'lat': point.latitude,
  'lon': point.longitude,
};

class LongdoMapView extends StatefulWidget {
  const LongdoMapView({
    super.key,
    this.point,
    this.onPointPicked,
    this.onReady,
    this.interactive = true,
    this.zoom = _defaultZoom,
    this.showLeftControls = true,
    this.preferThaiLabels = false,
    this.waitForFirstFrame = false,
    this.collapseAttribution = false,
  });

  static const _defaultZoom = 15.0;
  static const pickupZoom = 16.0;

  static bool get isAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      AppConfig.longdoMapApiKey.isNotEmpty;

  static Future<bool> preloadPicker(Future<LatLng?> point) =>
      isAvailable ? _LongdoMapPage.preloadPicker(point) : Future.value(false);

  final LatLng? point;
  final ValueChanged<LatLng>? onPointPicked;
  final ValueChanged<bool>? onReady;
  final bool interactive;
  final double zoom;
  final bool showLeftControls;
  final bool preferThaiLabels;
  final bool waitForFirstFrame;
  final bool collapseAttribution;

  @override
  State<LongdoMapView> createState() => LongdoMapViewState();
}

class LongdoMapViewState extends State<LongdoMapView> {
  _LongdoMapPage? _page;
  int _loadId = 0;
  int _requestId = 0;
  final _searches = <int, Completer<List<PickupLocation>>>{};
  final _pinAddresses = <int, Completer<Object?>>{};
  Completer<String?>? _route;
  Timer? _loadTimeout;
  bool _ready = false;
  bool _failed = false;
  LatLng? _initialPoint;
  LatLng? _pickedPoint;

  @override
  void initState() {
    super.initState();
    if (LongdoMapView.isAvailable) unawaited(_load());
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 18), _fail);
    try {
      final page = await _LongdoMapPage.open(
        picker: widget.onPointPicked != null,
      );
      if (!_isLoading(loadId)) return;
      page.onMessage = _message;
      page.onError = _fail;
      setState(() => _page = page);
      await WidgetsBinding.instance.endOfFrame;
      final sdkReady = await page.sdkReady.future.timeout(
        const Duration(seconds: 18),
      );
      if (!_isLoading(loadId)) return;
      if (!sdkReady) {
        _fail();
        return;
      }
      final point = _initialPoint = widget.point;
      await _call('start', [
        _coordinates(point ?? const LatLng(13.7563, 100.5018)),
        point == null && widget.onPointPicked == null ? 12.0 : widget.zoom,
        widget.onPointPicked != null,
        {
          'showLeftControls': widget.showLeftControls,
          'preferThaiLabels': widget.preferThaiLabels,
          'waitForFirstFrame': widget.waitForFirstFrame,
          'collapseAttribution': widget.collapseAttribution,
        },
      ]);
    } catch (_) {
      if (_isLoading(loadId)) _fail();
    }
  }

  bool _isLoading(int loadId) => mounted && loadId == _loadId && !_failed;

  Future<void> _call(String method, List<Object?> args) =>
      _page!.call(method, args);

  Future<void> _updatePin({required bool recenter, double? zoom}) async {
    final point = widget.point;
    try {
      await _call('setPin', [
        if (point != null) _coordinates(point) else null,
        recenter,
        zoom,
      ]);
    } catch (_) {
      _fail();
    }
  }

  void _message(String raw) {
    final Object? message;
    try {
      message = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (message is! Map || _failed) return;
    final data = message['data'];
    switch (message['type']) {
      case 'ready' when !_ready:
        _loadTimeout?.cancel();
        setState(() => _ready = true);
        widget.onReady?.call(true);
        unawaited(
          _updatePin(
            recenter: widget.point != _initialPoint,
            zoom: _initialPoint == null ? widget.zoom : null,
          ),
        );
      case 'error':
        _fail();
      case 'pick' when data is Map:
        final point = mapPoint(data['lat'], data['lon']);
        if (point == null) return;
        _pickedPoint = point;
        widget.onPointPicked?.call(point);
      case 'search' when data is Map:
        final request = _searches.remove(data['requestId']);
        if (request == null) return;
        try {
          request.complete(parseLongdoPlaces(data['result']));
        } on FormatException catch (error) {
          request.completeError(error);
        }
      case 'pin-address' when data is Map:
        _pinAddresses.remove(data['requestId'])?.complete(data['result']);
      case 'route':
        final route = _route;
        if (route != null && !route.isCompleted) {
          route.complete(data?.toString());
        }
    }
  }

  @override
  void didUpdateWidget(covariant LongdoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && oldWidget.point != widget.point) {
      unawaited(
        _updatePin(
          recenter: widget.point != _pickedPoint,
          zoom: oldWidget.point == null ? widget.zoom : null,
        ),
      );
    }
    _pickedPoint = null;
  }

  Future<void> centerOn(LatLng point) =>
      _mapAction('centerOn', [_coordinates(point)]);
  Future<void> fitRoute() => _mapAction('fitRoute', const []);

  Future<void> _mapAction(String method, List<Object?> args) async {
    if (!_ready) return;
    try {
      await _call(method, args);
    } catch (_) {
      _fail();
    }
  }

  Future<List<PickupLocation>> search(String query) async {
    if (!_ready) throw StateError('Map is not ready');
    final id = ++_requestId;
    final result = Completer<List<PickupLocation>>();
    _searches[id] = result;
    try {
      await _call('searchPlaces', [query, id]);
      return await result.future.timeout(const Duration(seconds: 10));
    } finally {
      _searches.remove(id);
    }
  }

  Future<PickupLocation?> addressAt(LatLng point) async {
    if (!_ready) return null;
    final id = ++_requestId;
    final result = _pinAddresses[id] = Completer<Object?>();
    try {
      await _call('addressAt', [_coordinates(point), id]);
      final payload = await result.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      return parseLongdoPinAddress(payload, point);
    } finally {
      _pinAddresses.remove(id);
    }
  }

  Future<String?> showRoute(
    LatLng origin,
    LatLng destination, {
    bool lockMarkers = false,
  }) async {
    if (!_ready || _route != null) return null;
    final result = _route = Completer<String?>();
    try {
      await _call('showRoute', [
        _coordinates(origin),
        _coordinates(destination),
        lockMarkers,
      ]);
      return await result.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } finally {
      _route = null;
    }
  }

  void _fail() {
    if (!mounted || _failed) return;
    _detachPage();
    setState(() {
      _ready = false;
      _failed = true;
    });
    _loadTimeout?.cancel();
    widget.onReady?.call(false);
  }

  void _detachPage() {
    _page?.onMessage = null;
    _page?.onError = null;
    _page = null;
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _detachPage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('โหลดแผนที่อีกครั้ง'),
          onPressed: () {
            setState(() => _failed = false);
            unawaited(_load());
          },
        ),
      );
    }
    final controller = _page?.controller;
    return ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            IgnorePointer(
              ignoring:
                  !widget.interactive || (widget.waitForFirstFrame && !_ready),
              child: WebViewWidget(
                key: ValueKey(controller),
                controller: controller,
                gestureRecognizers: widget.interactive
                    ? {
                        Factory<EagerGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      }
                    : const {},
              ),
            ),
          if (!_ready)
            const Center(
              child: IgnorePointer(
                child: Text(
                  'กำลังเปิดแผนที่…',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LongdoMapPage {
  static Future<_LongdoMapPage>? _pickerPage;
  static Future<bool>? _pickerPreparation;
  static Timer? _pickerExpiry;

  final controller = WebViewController();
  final sdkReady = Completer<bool>();
  final mapPreloaded = Completer<bool>();
  ValueChanged<String>? onMessage;
  VoidCallback? onError;

  Future<void> call(String method, List<Object?> args) =>
      controller.runJavaScript('$method(${args.map(jsonEncode).join(',')})');

  static Future<bool> preloadPicker(Future<LatLng?> point) {
    final existing = _pickerPreparation;
    if (existing != null) return existing;
    final pending = _pickerPage = _load();
    // เก็บ WebView สำหรับหน้าเลือกจุดนัดไว้ชั่วคราวเพียงหนึ่งตัว
    _pickerExpiry = Timer(const Duration(seconds: 45), _clearPicker);
    return _pickerPreparation = _preparePicker(pending, point);
  }

  static Future<bool> _preparePicker(
    Future<_LongdoMapPage> pending,
    Future<LatLng?> point,
  ) async {
    try {
      final page = await pending;
      final (loaded, center) = await (
        page.sdkReady.future.timeout(
          const Duration(seconds: 18),
          onTimeout: () => false,
        ),
        point,
      ).wait;
      if (!identical(pending, _pickerPage)) return false;
      if (!loaded) {
        _clearPicker();
        return false;
      }
      if (center == null) return false;
      await page.call('start', [
        _coordinates(center),
        LongdoMapView.pickupZoom,
        true,
        {'preload': true},
      ]);
      return await page.mapPreloaded.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (_) {
      if (identical(pending, _pickerPage)) _clearPicker();
      return false;
    }
  }

  static void _clearPicker() {
    _pickerExpiry?.cancel();
    _pickerExpiry = null;
    _pickerPage = null;
    _pickerPreparation = null;
  }

  static Future<_LongdoMapPage> open({required bool picker}) async {
    final pending = picker ? _pickerPage : null;
    if (pending != null) {
      _clearPicker();
      try {
        final page = await pending;
        if (!page.mapPreloaded.isCompleted) page.mapPreloaded.complete(false);
        return page;
      } catch (_) {
        // หากเตรียม WebView ล่วงหน้าไม่สำเร็จ ให้เริ่มโหลดเมื่อเปิดหน้า
      }
    }
    return _load();
  }

  static Future<_LongdoMapPage> _load() async {
    final page = _LongdoMapPage();
    final (html, app) = await (
      rootBundle.loadString('assets/maps/longdo.html'),
      PackageInfo.fromPlatform(),
    ).wait;
    final base = Uri.https(app.packageName, '/').toString();
    final sdk = Uri.https('api.longdo.com', '/map3/', {
      'key': AppConfig.longdoMapApiKey,
    });
    final controller = page.controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'YuemnoiMap',
      onMessageReceived: (message) {
        switch (message.message) {
          case 'sdk-ready':
          case 'sdk-error':
            if (!page.sdkReady.isCompleted) {
              page.sdkReady.complete(message.message == 'sdk-ready');
            }
          case 'map-preloaded':
          case 'map-preload-error':
            if (!page.mapPreloaded.isCompleted) {
              page.mapPreloaded.complete(message.message == 'map-preloaded');
            }
          default:
            page.onMessage?.call(message.message);
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            request.url == base || request.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (error) {
          if (error.isForMainFrame != true) return;
          if (!page.sdkReady.isCompleted) page.sdkReady.complete(false);
          page.onError?.call();
        },
      ),
    );
    await controller.loadHtmlString(
      html.replaceFirst(
        '__YUEMNOI_LONGDO_SDK_URL__',
        jsonEncode(sdk.toString()),
      ),
      baseUrl: base,
    );
    return page;
  }
}
