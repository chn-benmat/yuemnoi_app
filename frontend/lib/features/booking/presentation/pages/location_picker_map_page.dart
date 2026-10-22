import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_text_styles.dart';

/// ผลลัพธ์ที่ได้จากการเลือกและปักหมุดบนแผนที่
class LocationPickerResult {
  final String locationName;
  final String locationNote;
  final double latitude;
  final double longitude;
  final String fullAddress;

  const LocationPickerResult({
    required this.locationName,
    required this.locationNote,
    required this.latitude,
    required this.longitude,
    required this.fullAddress,
  });
}

class LocationPickerMapPage extends StatefulWidget {
  const LocationPickerMapPage({
    super.key,
    this.locationService,
    this.initialLocationName,
    this.initialNote,
    this.initialLatitude,
    this.initialLongitude,
  });

  final LocationService? locationService;
  final String? initialLocationName;
  final String? initialNote;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<LocationPickerMapPage> createState() => _LocationPickerMapPageState();
}

class _LocationPickerMapPageState extends State<LocationPickerMapPage>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late LatLng _currentCenter;
  double _currentZoom = 16.0;

  late final TextEditingController _nameController;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false;
  bool _isReverseGeocoding = false;
  bool _isLocatingUser = false;
  List<LocationSearchResult> _searchResults = [];
  int _searchVersion = 0;
  String? _searchMessage;
  String _lastSearchText = '';
  LocationService get _locationService =>
      widget.locationService ?? LocationService.instance;
  Timer? _geocodeTimer;
  Timer? _searchDebounce;

  String _resolvedAddress = '';
  bool _selectedApproximate = false;
  String? _selectedOriginalName;
  int _geocodeVersion = 0;
  late AnimationController _pinAnimController;
  late Animation<double> _pinJumpAnimation;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // กำหนดพิกัดเริ่มต้น
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _currentCenter = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
    } else {
      _currentCenter = LocationService.defaultBangkokLocation;
    }

    _nameController = TextEditingController(
      text: widget.initialLocationName ?? 'ซีคอน บางแค',
    );
    _searchController = TextEditingController();

    _pinAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _pinJumpAnimation = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _pinAnimController, curve: Curves.easeOut),
    );

    _searchController.addListener(_onSearchQueryChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    // ทำ Reverse Geocoding เพื่อดึงที่อยู่เริ่มต้น
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerReverseGeocode(_currentCenter);
    });
  }

  @override
  void dispose() {
    ++_searchVersion;
    _searchDebounce?.cancel();
    _geocodeTimer?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _pinAnimController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_searchFocusNode.hasFocus) {
        _searchMessage = _searchController.text.trim().isEmpty
            ? 'พิมพ์ชื่อสถานที่หรือที่อยู่อย่างน้อย 2 ตัวอักษร'
            : _searchMessage;
      } else {
        _searchDebounce?.cancel();
        ++_searchVersion;
        _searchResults = [];
        _searchMessage = null;
        _isSearching = false;
      }
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    ++_searchVersion;
    _searchFocusNode.unfocus();
    if (mounted) {
      setState(() {
        _searchResults = [];
        _searchMessage = null;
        _isSearching = false;
      });
    }
  }

  void _onSearchQueryChanged() {
    if (_searchController.text == _lastSearchText) return;
    _lastSearchText = _searchController.text;
    _searchDebounce?.cancel();
    ++_searchVersion;
    if (!mounted) return;
    final query = _searchController.text.trim();
    final canSuggest =
        _searchFocusNode.hasFocus &&
        query.runes.length >= 2 &&
        query.runes.length <= 200;
    setState(() {
      _searchResults = [];
      _isSearching = canSuggest;
      _searchMessage = canSuggest
          ? null
          : 'พิมพ์ชื่อสถานที่หรือที่อยู่อย่างน้อย 2 ตัวอักษร';
    });
    if (canSuggest) {
      _searchDebounce = Timer(
        const Duration(milliseconds: 600),
        () => _loadSearch(suggestions: true),
      );
    }
  }

  Future<void> _submitSearch([String? _]) => _loadSearch();

  Future<void> _loadSearch({bool suggestions = false}) async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    final version = ++_searchVersion;
    if (query.runes.length < 2 || query.runes.length > 200) {
      setState(() => _searchMessage = 'กรุณาระบุคำค้นหา 2–200 ตัวอักษร');
      return;
    }
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _searchMessage = null;
    });
    try {
      final results = suggestions
          ? await _locationService.suggestLocations(query)
          : await _locationService.searchLocations(query);
      if (!mounted || version != _searchVersion || !_searchFocusNode.hasFocus)
        return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _searchMessage = results.isEmpty
            ? 'ไม่พบสถานที่ ลองเพิ่มถนน เขต หรือจังหวัด หรือเลือกจุดบนแผนที่'
            : null;
      });
    } catch (_) {
      if (!mounted || version != _searchVersion || !_searchFocusNode.hasFocus)
        return;
      setState(() {
        _isSearching = false;
        _searchMessage =
            'ค้นหาสถานที่ไม่ได้ ลองแก้คำค้นหรือกดค้นหาบนคีย์บอร์ดอีกครั้ง';
      });
    }
  }

  void _triggerReverseGeocode(
    LatLng latLng, {
    bool updateLocationName = false,
  }) {
    _geocodeTimer?.cancel();
    final version = ++_geocodeVersion;
    setState(() {
      _isReverseGeocoding = true;
      _resolvedAddress = '';
      _selectedApproximate = false;
    });
    _geocodeTimer = Timer(const Duration(milliseconds: 400), () async {
      final result = await _locationService.reverseGeocode(
        latLng.latitude,
        latLng.longitude,
      );
      if (!mounted || version != _geocodeVersion) return;
      setState(() {
        _resolvedAddress =
            result?.displayName ??
            '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
        if (result != null) {
          _selectedOriginalName = result.originalName;
          if (updateLocationName ||
              _nameController.text == result.originalName) {
            _nameController.text = result.name;
          }
        }
        _isReverseGeocoding = false;
      });
    });
  }

  void _animateMapTo(
    LatLng target, {
    double? zoom,
    bool updateLocationName = true,
  }) {
    final targetZoom = zoom ?? _currentZoom;
    _pinAnimController.forward().then((_) => _pinAnimController.reverse());
    _mapController.move(target, targetZoom);
    setState(() {
      _currentCenter = target;
      _currentZoom = targetZoom;
    });
    _triggerReverseGeocode(target, updateLocationName: updateLocationName);
  }

  Future<void> _handleGoToCurrentLocation() async {
    setState(() => _isLocatingUser = true);
    final pos = await _locationService.getCurrentPosition();
    if (!mounted) return;
    setState(() => _isLocatingUser = false);

    if (pos != null) {
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      _animateMapTo(userLatLng, zoom: 16.5);
    } else {
      showAppPopup(
        context,
        content: Text(
          'ไม่สามารถดึงตำแหน่งปัจจุบันได้ กรุณาเปิด GPS และอนุญาตการเข้าถึง',
        ),
      );
    }
  }

  void _selectSearchResult(LocationSearchResult item) {
    _closeSearch();
    _searchController.clear();
    _geocodeTimer?.cancel();
    ++_geocodeVersion;
    _pinAnimController.forward().then((_) {
      if (mounted) _pinAnimController.reverse();
    });
    _mapController.move(item.latLng, 16.5);
    setState(() {
      _currentCenter = item.latLng;
      _currentZoom = 16.5;
      _selectedApproximate = item.isApproximate;
      _selectedOriginalName = item.originalName;
      _nameController.text = item.name;
      _resolvedAddress = item.displayName;
      _isReverseGeocoding = false;
      _searchMessage = null;
    });
  }

  void _onConfirmLocation() {
    final name = _nameController.text.trim();
    final initialNote = widget.initialNote?.trim() ?? '';
    if (name.isEmpty) {
      showAppPopup(context, content: Text('กรุณาระบุชื่อสถานที่นัดพบ'));
      return;
    }

    final result = LocationPickerResult(
      locationName: name,
      locationNote: initialNote,
      latitude: _currentCenter.latitude,
      longitude: _currentCenter.longitude,
      fullAddress: _resolvedAddress,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 1. แผนที่ Interactive (Google Maps Clean Style)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: _currentZoom,
              minZoom: 4,
              maxZoom: 20,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_searchFocusNode.hasFocus ||
                      _searchResults.isNotEmpty ||
                      _isSearching) {
                    _closeSearch();
                  }
                  _currentCenter = camera.center;
                  _currentZoom = camera.zoom;
                  _triggerReverseGeocode(
                    camera.center,
                    updateLocationName: true,
                  );
                }
              },
              onTap: (tapPosition, point) {
                if (_searchFocusNode.hasFocus ||
                    _searchResults.isNotEmpty ||
                    _isSearching) {
                  _closeSearch();
                } else {
                  _animateMapTo(point);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&hl=th&gl=th',
                subdomains: const ['0', '1', '2', '3'],
                userAgentPackageName: 'com.example.frontend',
                maxZoom: 20,
              ),
            ],
          ),

          // 2. หมุดปักกึ่งกลางแผนที่ (Center Marker Pin)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 38), // ชดเชยความสูงของหมุด
              child: AnimatedBuilder(
                animation: _pinJumpAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _pinJumpAnimation.value),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: Colors.amber,
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'ลากแผนที่เพื่อเลื่อนหมุด',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    Container(
                      width: 4,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2.5 พื้นหลังดักการแตะหน้าจอเพื่อออกจากโหมดค้นหา
          if (_searchFocusNode.hasFocus ||
              _searchResults.isNotEmpty ||
              _isSearching)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: Container(color: Colors.black.withValues(alpha: 0.12)),
              ),
            ),

          // 3. แถบค้นหาและตัวเลือกสถานที่ยอดนิยมด้านบน
          Positioned(
            // คงช่องพิมพ์เดิมไว้เมื่อเพิ่มพื้นหลังค้นหา เพื่อไม่ให้การเชื่อมต่อแป้นพิมพ์ถูกปิด
            key: const ValueKey('pickup-location-search'),
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // กล่องค้นหา
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submitSearch,
                    onEditingComplete: () {},
                    showCursor: true,
                    cursorColor: AppColors.primaryColor,
                    cursorWidth: 2,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2022),
                    ),
                    decoration: InputDecoration(
                      hintText: 'ค้นหาสถานที่, ห้าง, สถานี BTS/MRT...',
                      hintStyle: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primaryColor,
                        size: 22,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'ล้างคำค้นหา',
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: _searchController.clear,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),

                // รายการผลลัพธ์การค้นหาแบบ Dropdown List
                if (_searchFocusNode.hasFocus)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: BoxConstraints(
                      maxHeight:
                          (MediaQuery.sizeOf(context).height -
                                  MediaQuery.viewInsetsOf(context).bottom -
                                  MediaQuery.paddingOf(context).top -
                                  kToolbarHeight -
                                  120)
                              .clamp(60.0, 300.0),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Material(
                        color: Colors.transparent,
                        child: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.primaryColor,
                                    ),
                                  ),
                                ),
                              )
                            : _searchMessage != null
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(_searchMessage!),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0xFFF1F5F9),
                                ),
                                itemBuilder: (context, index) {
                                  final item = _searchResults[index];
                                  return ListTile(
                                    dense: true,
                                    leading: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryColor
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.place_rounded,
                                        color: AppColors.primaryColor,
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E2022),
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.isApproximate
                                          ? 'ถนน/พื้นที่ (ยังไม่พบเลขบ้าน)\n${item.displayName}'
                                          : item.displayName,
                                      maxLines: item.isApproximate ? 3 : 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 11.5,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    onTap: () => _selectSearchResult(item),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),

                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                    ),
                    child: const Text(
                      'ข้อมูลสถานที่ © OpenStreetMap contributors (ODbL)',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF334155),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                // ชิปสถานที่ยอดนิยม (Quick Landmark Chips)
                if (!_searchFocusNode.hasFocus)
                  Container(
                    height: 38,
                    margin: const EdgeInsets.only(top: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: LocationService.popularLandmarks.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final landmark =
                            LocationService.popularLandmarks[index];
                        final isSelected = _nameController.text.contains(
                          landmark.name,
                        );
                        return ActionChip(
                          backgroundColor: isSelected
                              ? AppColors.primaryColor
                              : Colors.white,
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primaryColor
                                : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                          label: Text(
                            landmark.name,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF334155),
                            ),
                          ),
                          avatar: Icon(
                            Icons.near_me_rounded,
                            size: 14,
                            color: isSelected
                                ? Colors.white
                                : AppColors.primaryColor,
                          ),
                          onPressed: () => _selectSearchResult(landmark),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 4. ปุ่มควบคุมลอยตัวด้านขวา (GPS Location & Zoom Buttons)
          if (!_searchFocusNode.hasFocus)
            Positioned(
              right: 16,
              bottom: 270,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ปุ่มตำแหน่งปัจจุบัน (GPS)
                  FloatingActionButton.small(
                    heroTag: 'fab-gps-location',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryColor,
                    elevation: 4,
                    tooltip: 'ตำแหน่งปัจจุบันของคุณ',
                    onPressed: _isLocatingUser
                        ? null
                        : _handleGoToCurrentLocation,
                    child: _isLocatingUser
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryColor,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, size: 20),
                  ),
                  const SizedBox(height: 8),

                  // ปุ่ม Zoom In
                  FloatingActionButton.small(
                    heroTag: 'fab-zoom-in',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF334155),
                    elevation: 4,
                    tooltip: 'ซูมเข้า',
                    onPressed: () {
                      _animateMapTo(
                        _currentCenter,
                        zoom: _currentZoom + 1,
                        updateLocationName: false,
                      );
                    },
                    child: const Icon(Icons.add_rounded, size: 22),
                  ),
                  const SizedBox(height: 6),

                  // ปุ่ม Zoom Out
                  FloatingActionButton.small(
                    heroTag: 'fab-zoom-out',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF334155),
                    elevation: 4,
                    tooltip: 'ซูมออก',
                    onPressed: () {
                      _animateMapTo(
                        _currentCenter,
                        zoom: _currentZoom - 1,
                        updateLocationName: false,
                      );
                    },
                    child: const Icon(Icons.remove_rounded, size: 22),
                  ),
                ],
              ),
            ),

          // 5. แถบข้อมูลสรุปและปุ่มยืนยันด้านล่าง (Bottom Confirmation Card)
          if (!_searchFocusNode.hasFocus)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle Bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      if (_selectedApproximate)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'ยังไม่พบเลขบ้าน กรุณาเลื่อนหมุดไปจุดนัดรับที่ต้องการ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      // ช่องแก้ไขชื่อสถานที่
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E2022),
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'ชื่อสถานที่นัดพบ...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_isReverseGeocoding)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryColor,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      if (_selectedOriginalName?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'ชื่อเดิม: $_selectedOriginalName',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      // รายละเอียดที่อยู่
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          _resolvedAddress.isNotEmpty
                              ? _resolvedAddress
                              : 'กำลังโหลดที่อยู่ตามพิกัด...',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ปุ่มยืนยันสถานที่นัดพบนี้
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          key: const ValueKey('confirm-location-picker-button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shadowColor: AppColors.primaryColor.withValues(
                              alpha: 0.35,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _isReverseGeocoding
                              ? null
                              : _onConfirmLocation,
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                          ),
                          label: const Text(
                            'ยืนยันสถานที่นัดพบนี้',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
