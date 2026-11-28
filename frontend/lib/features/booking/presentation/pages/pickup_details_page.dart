import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/models/pickup_location.dart';
import '../../../../core/widgets/longdo_map_view.dart';
import '../../../../core/widgets/map_control_button.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/map_device_position.dart';
import '../../../../core/theme/app_form_field_styles.dart';

class PickupDetailsPage extends StatefulWidget {
  const PickupDetailsPage({
    super.key,
    this.initialLocation,
    this.initialDevicePosition,
  });

  final PickupLocation? initialLocation;
  final Future<Position?>? initialDevicePosition;

  @override
  State<PickupDetailsPage> createState() => _PickupDetailsPageState();
}

class _PickupDetailsPageState extends State<PickupDetailsPage> {
  static const _unnamedPinLabel = 'จุดนัดรับที่ปักหมุด';

  final _formKey = GlobalKey<FormState>();
  final _map = GlobalKey<LongdoMapViewState>();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  LatLng? _pendingPin;
  bool _mapReady = false;
  bool _mapFailed = false;
  bool _searching = false;
  bool _showSearchResults = false;
  bool _searchFailed = false;
  int _searchRevision = 0;
  int _selectionRevision = 0;
  int _gpsRequestId = 0;
  List<PickupLocation> _places = const [];
  Timer? _searchDebounce;
  Timer? _pinLookupDebounce;

  late final _name = TextEditingController(text: widget.initialLocation?.name);
  late final _address = TextEditingController(
    text: widget.initialLocation?.address,
  );

  late final _point = ValueNotifier(
    mapPoint(
      widget.initialLocation?.latitude,
      widget.initialLocation?.longitude,
    ),
  );
  bool _locating = false;
  bool _waitingForInitialPosition = false;

  bool get _resolvingPin => _pendingPin != null;

  @override
  void initState() {
    super.initState();
    if (LongdoMapView.isAvailable && widget.initialLocation == null) {
      _waitingForInitialPosition = true;
      unawaited(_useCurrentLocation(automatic: true));
    }
  }

  PickupLocation get _location => PickupLocation(
    name: _name.text.trim(),
    address: _address.text.trim(),
    latitude: _point.value?.latitude,
    longitude: _point.value?.longitude,
  );

  void _scheduleSearch(String raw, {bool immediately = false}) {
    _searchDebounce?.cancel();
    final revision = ++_searchRevision;
    final query = raw.trim();
    final shouldSearch = query.runes.length >= 2;
    setState(() {
      _places = const [];
      _searchFailed = shouldSearch && _mapFailed;
      _showSearchResults = shouldSearch;
      _searching = shouldSearch && !_mapFailed;
    });
    if (!shouldSearch || !_mapReady) return;
    if (immediately) {
      unawaited(_findPlaces(query, revision));
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 650), () {
        unawaited(_findPlaces(query, revision));
      });
    }
  }

  Future<void> _findPlaces(String query, int revision) async {
    try {
      final places = await _map.currentState!.search(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _places = places;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  void _choosePlace(PickupLocation place) {
    FocusScope.of(context).unfocus();
    _search.clear();
    _cancelPinLookup();
    _scheduleSearch('');
    // ใช้ผลค้นหาเติมชื่อ ที่อยู่ และหมุดเพื่อให้ผู้ใช้ตรวจสอบก่อนยืนยัน
    _name.text = place.name;
    _address.text = place.address;
    _point.value = LatLng(place.latitude!, place.longitude!);
  }

  void _confirm() {
    final location = _location;
    if (_formKey.currentState?.validate() == false) return;
    if (!location.hasCoordinates) {
      _showLocationMessage('แตะหรือลากแผนที่เพื่อระบุจุดนัดรับ');
      return;
    }
    if (location.isValid) {
      Navigator.of(context).pop(_location);
    }
  }

  Future<void> _useCurrentLocation({bool automatic = false}) async {
    final requestId = ++_gpsRequestId;
    final selection = _selectionRevision;
    if (!automatic) setState(() => _locating = true);
    try {
      final prepared = automatic ? widget.initialDevicePosition : null;
      final position =
          await (prepared ??
              getMapDevicePosition(requestPermission: !automatic));
      if (!mounted ||
          requestId != _gpsRequestId ||
          selection != _selectionRevision) {
        return;
      }
      if (position == null) {
        if (!automatic) {
          _showLocationMessage('กรุณาอนุญาตการเข้าถึงตำแหน่งในการตั้งค่า');
        }
        return;
      }
      final point = mapPoint(position.latitude, position.longitude);
      if (point != null) _selectMapPoint(point, preserveSearch: automatic);
    } catch (_) {
      if (!automatic &&
          requestId == _gpsRequestId &&
          selection == _selectionRevision) {
        _showLocationMessage('อ่านตำแหน่งไม่ได้ กรุณาเปิด GPS แล้วลองอีกครั้ง');
      }
    } finally {
      if (mounted && (automatic || requestId == _gpsRequestId)) {
        setState(() {
          if (automatic) {
            _waitingForInitialPosition = false;
          } else {
            _locating = false;
          }
        });
      }
    }
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pinLookupDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _name.dispose();
    _address.dispose();
    _point.dispose();
    super.dispose();
  }

  void _selectMapPoint(LatLng point, {bool preserveSearch = false}) {
    if (point == _point.value) return;
    if (!preserveSearch && (_searchFocus.hasFocus || _showSearchResults)) {
      _searchFocus.unfocus();
      _search.clear();
      _scheduleSearch('');
    }
    _cancelPinLookup();
    _point.value = point;

    _address.clear();
    _name.text = _mapFailed ? _unnamedPinLabel : '';
    setState(() => _pendingPin = _mapFailed ? null : point);
    _resolvePendingPin();
  }

  void _cancelPinLookup() {
    _pinLookupDebounce?.cancel();
    _selectionRevision++;
    _pendingPin = null;
  }

  void _resolvePendingPin() {
    final point = _pendingPin;
    if (!_mapReady || point == null) return;
    final revision = _selectionRevision;
    _pinLookupDebounce?.cancel();
    _pinLookupDebounce = Timer(const Duration(milliseconds: 350), () async {
      PickupLocation? place;
      try {
        place = await _map.currentState?.addressAt(point);
      } catch (_) {
        // ใช้พิกัดเดิมต่อได้หาก Longdo ไม่ตอบกลับ
      }
      if (!mounted || revision != _selectionRevision) return;
      _name.text = place?.name ?? _unnamedPinLabel;
      _address.text = place?.address ?? '';
      setState(() => _pendingPin = null);
    });
  }

  Widget _buildMapLayout(
    InputDecoration decoration, {
    required bool keyboardIsOpen,
  }) => ListenableBuilder(
    listenable: _searchFocus,
    builder: (context, _) {
      final searching = _searchFocus.hasFocus && keyboardIsOpen;
      final compact = MediaQuery.sizeOf(context).height < 500;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('pickup-location-search'),
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _scheduleSearch,
              onSubmitted: (query) => _scheduleSearch(query, immediately: true),
              decoration: decoration.copyWith(
                hintText: 'ค้นหาสถานที่ ห้าง สถานี BTS/MRT หรือที่อยู่',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  if (_waitingForInitialPosition)
                    const ColoredBox(
                      color: Color(0xFFF1F5F9),
                      child: Center(
                        child: Text(
                          'กำลังหาตำแหน่งของคุณ…',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ValueListenableBuilder(
                      valueListenable: _point,
                      builder: (context, point, _) => LongdoMapView(
                        key: _map,
                        point: point,
                        zoom: LongdoMapView.pickupZoom,
                        onPointPicked: _selectMapPoint,
                        onReady: _onMapReady,
                      ),
                    ),
                  if (_mapReady && !searching && !compact)
                    Positioned(
                      right: 16,
                      bottom: 52,
                      child: _buildCurrentLocationButton(),
                    ),
                  if (_showSearchResults)
                    Positioned(
                      top: 0,
                      left: 16,
                      right: 16,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight.clamp(0.0, 265.0),
                        ),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: _buildSearchResults(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!searching) _buildMapConfirmation(showCompactControls: compact),
        ],
      );
    },
  );

  Widget _buildCurrentLocationButton() => MapControlButton(
    icon: Icons.my_location_rounded,
    tooltip: 'ตำแหน่งปัจจุบันของคุณ',
    color: AppColors.primaryColor,
    loading: _locating,
    onPressed: _useCurrentLocation,
  );

  Widget _buildMapConfirmation({
    required bool showCompactControls,
  }) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              0.53,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (showCompactControls && _mapReady)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(child: _buildCurrentLocationButton()),
                  ),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFF3E8FF),
                      foregroundColor: AppColors.primaryColor,
                      child: Icon(Icons.place_rounded, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: const Key('pickup-name'),
                        controller: _name,
                        readOnly: true,
                        canRequestFocus: false,
                        enableInteractiveSelection: false,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _resolvingPin
                              ? 'จุดนัดรับ'
                              : 'ปักหมุดหรือค้นหาสถานที่',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        validator: (_) =>
                            _location.isValid ? null : 'กรุณาเลือกจุดนัดรับ',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ListenableBuilder(
                  listenable: _address,
                  builder: (context, _) {
                    final address = _address.text.trim();
                    if (!_resolvingPin && address.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Text(
                          _resolvingPin ? 'กำลังระบุสถานที่จากหมุด…' : address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey('confirm-location-picker-button'),
                    onPressed:
                        _locating || _waitingForInitialPosition || _resolvingPin
                        ? null
                        : _confirm,
                    icon: const Icon(Icons.check_circle, size: 19),
                    label: const Text(
                      'ยืนยันสถานที่นัดพบนี้',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _onMapReady(bool ready) {
    if (!mounted) return;
    setState(() {
      _mapReady = ready;
      _mapFailed = !ready;
      if (!ready) {
        if (_resolvingPin) _name.text = _unnamedPinLabel;
        _cancelPinLookup();
      }
    });
    if (ready) _resolvePendingPin();
    if (_search.text.isNotEmpty) {
      _scheduleSearch(_search.text, immediately: true);
    }
  }

  Widget _buildSearchResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (_searchFailed || _places.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _searchFailed
              ? 'ค้นหาไม่ได้ ลองใหม่อีกครั้งหรือแตะแผนที่เพื่อปักหมุด'
              : 'ไม่พบสถานที่ ลองเปลี่ยนคำค้นหรือแตะแผนที่เพื่อปักหมุด',
        ),
      );
    }
    return Column(
      children: [
        for (final place in _places)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.name),
            subtitle: place.address.isEmpty ? null : Text(place.address),
            onTap: () => _choosePlace(place),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardIsOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final fieldDecoration = AppFormFieldStyles.decoration(
      context,
      variant: AppFormFieldVariant.outlined,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'เลือกจุดนัดรับอุปกรณ์',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: LongdoMapView.isAvailable
          ? _buildMapLayout(fieldDecoration, keyboardIsOpen: keyboardIsOpen)
          : const Center(child: Text('แผนที่ Longdo ยังไม่พร้อมใช้งาน')),
    );
  }
}
