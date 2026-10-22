import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/phone_call_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../booking/domain/entities/booking_request_model.dart';
import '../../widgets/rentals/rental_handover_modal.dart';
import '../../bloc/rental_route_cubit.dart';
import '../../../data/datasources/rental_contact_remote_data_source.dart';
import '../../../../chat/data/datasources/chat_remote_data_source.dart';

class RentalTrackingMapPage extends StatefulWidget {
  final BookingRequestData? bookingData;
  final String? itemTitle;
  final String? itemImageUrl;
  final String? pickupLocation;
  final String? pickupNote;
  final double? destinationLat;
  final double? destinationLng;
  final String? ownerName;
  final String? ownerPhone;
  final String? periodText;
  final double? totalPrice;
  final String? conversationId;
  final String? statusCode;
  final int? bookingId;
  final bool? isOwner;
  final LocationService? locationService;
  final RentalContactRemoteDataSource? contactDataSource;
  final PhoneCallService phoneCallService;

  const RentalTrackingMapPage({
    super.key,
    this.bookingData,
    this.itemTitle,
    this.itemImageUrl,
    this.pickupLocation,
    this.pickupNote,
    this.destinationLat,
    this.destinationLng,
    this.ownerName,
    this.ownerPhone,
    this.periodText,
    this.totalPrice,
    this.conversationId,
    this.statusCode,
    this.bookingId,
    this.isOwner,
    this.locationService,
    this.contactDataSource,
    this.phoneCallService = const UrlPhoneCallService(),
  });

  @override
  State<RentalTrackingMapPage> createState() => _RentalTrackingMapPageState();
}

class _RentalTrackingMapPageState extends State<RentalTrackingMapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  LocationService get _locationService =>
      widget.locationService ?? LocationService.instance;
  late final MapController _mapController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  LatLng? _userLocation;
  late LatLng _destinationLocation;
  DrivingRouteResult? _routeResult;

  bool _isLoadingRoute = true;
  bool _isSimulatedLocation = false;
  LatLng? _rawDeviceGps;
  bool _forceUseRawDeviceGps = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isAutoFollow = false;
  late final RentalRouteCubit _routeCubit;
  StreamSubscription<RentalRouteState>? _routeSubscription;

  // ข้อมูลที่ resolve แล้ว
  late String _resolvedTitle;
  late String? _resolvedImageUrl;
  late String _resolvedLocation;
  late String? _resolvedLocationNote;
  late String _resolvedOwnerName;
  late String _resolvedPeriod;
  late double _resolvedPrice;
  late String _currentStatusCode;
  late bool _isOwner;
  int _renterHandoverStep = 0;

  DateTime? get _startDate {
    return widget.bookingData?.startDate;
  }

  bool get _isBeforeMeetupDate {
    final start = _startDate;
    if (start == null) return false;
    final now = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    return today.isBefore(startDay);
  }

  int get _daysUntilMeetup {
    final start = _startDate;
    if (start == null) return 0;
    final now = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    return startDay.difference(today).inDays;
  }

  void _openPaymentOrHandover() {
    if (_isBeforeMeetupDate) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 8),
              Text(
                _isOwner ? 'ยังไม่ถึงวันนัดส่งมอบ' : 'ยังไม่ถึงวันนัดเช่า',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            'วันนัดรับอุปกรณ์คือ ${_startDate != null ? DateFormat('d MMMM yyyy', 'th').format(_startDate!) : 'ตามที่ตกลง'}\n\n${_isOwner ? 'ระบบจะเปิดให้ส่งมอบอุปกรณ์และตรวจสอบการชำระเงินในวันนัดรับของจริง เพื่อความปลอดภัยของผู้เช่าและผู้ปล่อยเช่า' : 'ระบบจะเปิดให้ตรวจรับสินค้าและชำระเงินในวันนัดรับของจริง เพื่อความปลอดภัยของผู้เช่าและผู้ปล่อยเช่า'}',
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'เข้าใจแล้ว',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showHandoverModal();
              },
              child: const Text(
                'ดูตัวอย่างหน้าตรวจรับ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    _showHandoverModal();
  }

  void _showHandoverModal() {
    RentalHandoverModal.show(
      context,
      bookingId: widget.bookingId,
      conversationId:
          widget.conversationId ?? widget.bookingData?.conversationId,
      itemId: widget.bookingData?.item.id,
      itemTitle: _resolvedTitle,
      itemImageUrl: _resolvedImageUrl,
      ownerName: _resolvedOwnerName,
      renterName: 'ผู้เช่า',
      totalPrice: _resolvedPrice,
      paymentMethod: widget.bookingData?.paymentMethod ?? 'promptpay',
      initialIsOwner: _isOwner,
      initialStep: _renterHandoverStep,
      onStepChanged: (step) {
        if (mounted) {
          setState(() {
            _renterHandoverStep = step;
          });
        }
      },
      onHandoverSuccess: (newStatus) {
        setState(() {
          _currentStatusCode = newStatus;
          _renterHandoverStep = 0;
        });
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _resolveInitialData();
    WidgetsBinding.instance.addObserver(this);
    _routeCubit = RentalRouteCubit(
      destination: _destinationLocation,
      fetchRoute: _locationService.fetchDrivingRoute,
      cachedRoute: _locationService.cachedDrivingRoute,
      isVisible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false),
    );
    _routeSubscription = _routeCubit.stream.listen((state) {
      if (!mounted) return;
      final firstRoute = _routeResult == null && state.route != null;
      setState(() {
        _routeResult = state.route;
        _isLoadingRoute = state.loading;
      });
      if (firstRoute)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitBoundsToRoute();
        });
    });
    if (_hasDestinationCoordinates) _initLocationsAndRoute();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _routeCubit.setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeSubscription?.cancel();
    _routeCubit.close();
    _positionStreamSubscription?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _resolveInitialData() {
    final b = widget.bookingData;
    _resolvedTitle = b?.item.title ?? widget.itemTitle ?? 'อุปกรณ์เช่า';
    _resolvedImageUrl = b?.item.imageUrl ?? widget.itemImageUrl;
    _resolvedLocation = b?.location ?? widget.pickupLocation ?? 'สยามพารากอน';
    _resolvedLocationNote = b?.locationNote ?? widget.pickupNote;
    _resolvedOwnerName =
        b?.item.ownerName ?? widget.ownerName ?? 'ผู้ปล่อยเช่า';
    _resolvedPeriod = b != null
        ? b.formattedPeriodSummary
        : (widget.periodText ?? '1 วัน');
    _resolvedPrice = b?.totalPrice ?? widget.totalPrice ?? 0.0;
    _currentStatusCode = widget.statusCode ?? 'confirmed';
    _isOwner = widget.isOwner ?? false;

    // Resolve Destination Coordinates
    // พิกัดจุดรับเป็นของประกาศอุปกรณ์ เลือกโดยเจ้าของตอนเพิ่มอุปกรณ์
    final destLat = b?.latitude ?? b?.item.latitude ?? widget.destinationLat;
    final destLng = b?.longitude ?? b?.item.longitude ?? widget.destinationLng;

    if (_hasDestinationCoordinates) {
      _destinationLocation = LatLng(destLat!, destLng!);
    } else {
      final fallback = LocationService.resolveCoordinates(
        locationName: _resolvedLocation,
      );
      _destinationLocation = LatLng(fallback.latitude, fallback.longitude);
    }

    _loadSavedHandoverStep();
  }

  Future<void> _loadSavedHandoverStep() async {
    final step = await RentalHandoverModal.getSavedStep(
      bookingId: widget.bookingId,
      conversationId:
          widget.conversationId ?? widget.bookingData?.conversationId,
      itemId: widget.bookingData?.item.id,
      itemTitle: _resolvedTitle,
    );
    if (mounted) {
      setState(() {
        _renterHandoverStep = step;
      });
    }
  }

  Future<void> _initLocationsAndRoute() async {
    setState(() {
      _isLoadingRoute = _routeResult == null;
    });

    // เริ่มจากพิกัดล่าสุดก่อน ระหว่างรอ GPS ใหม่ที่อาจใช้เวลาหลายวินาที
    final lastKnown = await _locationService.getLastKnownPosition();
    if (!mounted) return;
    if (lastKnown != null) {
      final point = LatLng(lastKnown.latitude, lastKnown.longitude);
      if (const Distance().as(
                LengthUnit.Kilometer,
                point,
                _destinationLocation,
              ) <=
              500 ||
          _forceUseRawDeviceGps) {
        setState(() => _userLocation = point);
        _routeCubit.updatePosition(point);
      }
    }

    // 1. ดึงตำแหน่ง GPS ของตัวเรา
    LatLng userPos;
    bool isSimulated = false;
    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        final rawLatLng = LatLng(pos.latitude, pos.longitude);
        _rawDeviceGps = rawLatLng;

        const distanceCalc = Distance();
        final distanceKm = distanceCalc.as(
          LengthUnit.Kilometer,
          rawLatLng,
          _destinationLocation,
        );

        // หากตำแหน่งอยู่ไกลกว่า 500 กม. (มักเกิดจากการทดสอบบน Emulator ที่ค่าเริ่มต้นของพิกัดอยู่สหรัฐฯ หรือ ยุโรป เช่น ลิสบอน/สเปน)
        if (!_forceUseRawDeviceGps && distanceKm > 500) {
          isSimulated = true;
          // จำลองตำแหน่งในกรุงเทพฯ ห่างจากจุดนัดรับประมาณ 2.5 กม. เพื่อให้เห็นเส้นทางการเดินทางจริง
          userPos = LatLng(
            _destinationLocation.latitude - 0.018,
            _destinationLocation.longitude - 0.015,
          );
        } else {
          userPos = rawLatLng;
        }
      } else {
        isSimulated = true;
        // Fallback ตำแหน่งจำลองในกรุงเทพฯ ห่างจากจุดนัดรับเล็กน้อย เพื่อให้เห็นเส้นทางชัดเจน
        userPos = LatLng(
          _destinationLocation.latitude - 0.018,
          _destinationLocation.longitude - 0.015,
        );
      }
    } catch (_) {
      isSimulated = true;
      userPos = LatLng(
        _destinationLocation.latitude - 0.018,
        _destinationLocation.longitude - 0.015,
      );
    }

    if (!mounted) return;
    setState(() {
      _userLocation = userPos;
      _isSimulatedLocation = isSimulated;
    });

    _routeCubit.updatePosition(userPos);
    _startLiveLocationTracking();
  }

  /// สตรีมติดตามตำแหน่งพิกัดแบบ Real-time
  void _startLiveLocationTracking() {
    _positionStreamSubscription?.cancel();
    try {
      final stream = _locationService.getPositionStream(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
      if (stream != null) {
        _positionStreamSubscription = stream.listen(
          (Position pos) {
            _onRealtimePositionUpdated(pos);
          },
          onError: (e) {
            debugPrint('Live position stream error: $e');
          },
        );
      }
    } catch (e) {
      debugPrint('Cannot start live position stream: $e');
    }
  }

  /// เมื่อได้รับพิกัดใหม่จากการเคลื่อนที่จริงหรือ Emulator
  void _onRealtimePositionUpdated(Position pos) {
    if (!mounted) return;
    final newGps = LatLng(pos.latitude, pos.longitude);
    _rawDeviceGps = newGps;

    const distanceCalc = Distance();
    final distKm = distanceCalc.as(
      LengthUnit.Kilometer,
      newGps,
      _destinationLocation,
    );

    // ถ้าพิกัดยังอยู่ไกลเกิน 500 กม. และไม่ได้กดบังคับใช้ GPS จริง ให้คงการจำลองไว้
    if (!_forceUseRawDeviceGps && distKm > 500) {
      return;
    }

    // อัปเดตตำแหน่งหมุดทันทีแบบ Real-time
    setState(() {
      _userLocation = newGps;
      if (distKm <= 500) {
        _isSimulatedLocation = false;
      }
    });

    // หากเปิดโหมดติดตามตำแหน่งอัตโนมัติ ให้เลื่อนกล้องตามหมุด
    if (_isAutoFollow) {
      _mapController.move(newGps, _mapController.camera.zoom);
    }

    _routeCubit.updatePosition(newGps);
  }

  /// ดึงข้อมูลเส้นทางใหม่สำหรับพิกัดเริ่มต้นที่ระบุ
  Future<void> _fetchRouteForPosition(LatLng startPos) async {
    _routeCubit.updatePosition(startPos);
  }

  /// จำลองการขยับตำแหน่งตัวเรา (เมื่อแตะบนแผนที่ในโหมดจำลอง)
  void _simulateMoveTo(LatLng point) {
    setState(() {
      _userLocation = point;
    });
    if (_isAutoFollow) {
      _mapController.move(point, _mapController.camera.zoom);
    }
    _fetchRouteForPosition(point);
  }

  void _fitBoundsToRoute() {
    if (_userLocation == null) return;
    try {
      final points = _routeResult?.points.isNotEmpty == true
          ? _routeResult!.points
          : [_userLocation!, _destinationLocation];

      final bounds = LatLngBounds.fromPoints(points);

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(48, 100, 48, 300),
        ),
      );
    } catch (_) {
      _mapController.move(_destinationLocation, 14.5);
    }
  }

  void _centerToUser() {
    if (_userLocation != null) {
      setState(() {
        _isAutoFollow = true;
      });
      _mapController.move(_userLocation!, 16.0);
    }
  }

  void _centerToDestination() {
    _mapController.move(_destinationLocation, 16.0);
  }

  Future<void> _openExternalNavigation() async {
    await LocationService.openInExternalMaps(
      _destinationLocation.latitude,
      _destinationLocation.longitude,
    );
  }

  bool _calling = false;

  Future<void> _callOwner() async {
    if (_calling) return;
    _calling = true;
    try {
      final phone =
          await (widget.contactDataSource ?? RentalContactRemoteDataSource())
              .getPhone(
                bookingId: widget.bookingId,
                conversationId:
                    widget.conversationId ?? widget.bookingData?.conversationId,
              );
      if (!mounted) return;
      if (phone.trim().isEmpty) {
        throw const ChatRemoteException('ผู้ใช้นี้ยังไม่ได้เพิ่มเบอร์โทรศัพท์');
      }
      if (!await widget.phoneCallService.call(phone)) {
        throw const ChatRemoteException('ไม่สามารถเปิดแอปโทรได้');
      }
    } catch (error) {
      if (mounted) {
        showAppPopup(
          context,
          content: Text(
            error is ChatRemoteException
                ? error.message
                : 'ไม่สามารถโหลดข้อมูลติดต่อได้ กรุณาลองใหม่',
          ),
        );
      }
    } finally {
      _calling = false;
    }
  }

  bool get _hasDestinationCoordinates {
    final lat =
        widget.bookingData?.latitude ??
        widget.bookingData?.item.latitude ??
        widget.destinationLat;
    final lng =
        widget.bookingData?.longitude ??
        widget.bookingData?.item.longitude ??
        widget.destinationLng;
    return lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasDestinationCoordinates)
      return Scaffold(
        appBar: AppBar(title: const Text('จุดนัดรับสินค้า')),
        body: const Center(
          child: Text('การจองนี้ยังไม่มีพิกัดจุดนัดรับ กรุณาติดต่อคู่เช่า'),
        ),
      );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ─── 1. แผนที่ Interactive (FlutterMap) ───
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _destinationLocation,
              initialZoom: 14.5,
              minZoom: 4,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isAutoFollow) {
                  setState(() {
                    _isAutoFollow = false;
                  });
                }
              },
              onTap: (tapPosition, point) {
                if (_isSimulatedLocation) {
                  _simulateMoveTo(point);
                }
              },
            ),
            children: [
              // TileLayer Google Maps Clean Style
              TileLayer(
                urlTemplate:
                    'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['0', '1', '2', '3'],
                userAgentPackageName: 'com.example.frontend',
                maxZoom: 19,
              ),

              // Polyline เส้นทางถนนจริง (OSRM Route)
              if (_routeResult != null && _routeResult!.points.isNotEmpty) ...[
                // เงา/ขอบเส้นทางด้านล่าง
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeResult!.points,
                      color: const Color(0xFF4C1D95).withValues(alpha: 0.35),
                      strokeWidth: 8.5,
                    ),
                  ],
                ),
                // เส้นทางสีม่วงหลัก
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeResult!.points,
                      color: AppColors.primaryColor,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
              ],

              // หมุด Marker บนแผนที่
              MarkerLayer(
                markers: [
                  // 1) หมุดตัวเรา (User Location)
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 90,
                      height: 90,
                      child: _buildUserMarker(),
                    ),

                  // 2) หมุดจุดนัดรับ (Destination Location)
                  Marker(
                    point: _destinationLocation,
                    width: 140,
                    height: 100,
                    child: _buildDestinationMarker(),
                  ),
                ],
              ),
            ],
          ),

          // ─── 2. Floating Top AppBar ───
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // ปุ่มย้อนกลับ
                  _buildGlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  // แถบหัวข้อสถานะ
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'เส้นทางนัดรับอุปกรณ์',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E2022),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── แถบแจ้งเตือนจำลองพิกัดสำหรับ Emulator ───
          if (_isSimulatedLocation)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.devices_other_rounded,
                      color: Color(0xFF38BDF8),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'จำลองตำแหน่งใน กทม. (แตะแผนที่เพื่อขยับหมุดทดสอบ หรือเปลี่ยน GPS บน Emulator ได้)',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_rawDeviceGps != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _forceUseRawDeviceGps = true;
                          });
                          if (_hasDestinationCoordinates)
                            _initLocationsAndRoute();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ใช้ GPS จริง',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          if (_forceUseRawDeviceGps &&
              !_isSimulatedLocation &&
              _rawDeviceGps != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFB45309).withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'กำลังแสดงพิกัดจริงของ GPS เครื่อง',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _forceUseRawDeviceGps = false;
                        });
                        if (_hasDestinationCoordinates)
                          _initLocationsAndRoute();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'จำลองใน กทม.',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── 3. Floating Action Controls (ฝั่งขวา) ───
          Positioned(
            right: 16,
            bottom: 310,
            child: Column(
              children: [
                // ปุ่ม Fit Bounds (ดูภาพรวมทั้งสองจุด)
                _buildMapFloatingButton(
                  icon: Icons.crop_free_rounded,
                  tooltip: 'ดูภาพรวมเส้นทาง',
                  onTap: _fitBoundsToRoute,
                ),
                const SizedBox(height: 10),
                // ปุ่มนำทาง Google Maps ภายนอก
                _buildMapFloatingButton(
                  icon: Icons.near_me_rounded,
                  tooltip: 'นำทางด้วย Google Maps',
                  color: const Color(0xFF10B981),
                  iconColor: Colors.white,
                  onTap: _openExternalNavigation,
                ),
                const SizedBox(height: 10),
                // ปุ่มพิกัดตัวเรา
                _buildMapFloatingButton(
                  icon: Icons.my_location_rounded,
                  tooltip: _isAutoFollow
                      ? 'กำลังติดตามตำแหน่ง (Real-time)'
                      : 'ตำแหน่งของฉัน',
                  color: _isAutoFollow ? AppColors.primaryColor : Colors.white,
                  iconColor: _isAutoFollow
                      ? Colors.white
                      : const Color(0xFF1E2022),
                  onTap: _centerToUser,
                ),
              ],
            ),
          ),

          // ─── 4. แผงข้อมูลด้านล่าง (Bolt / Grab Tracking Card) ───
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildTrackingBottomCard(context),
          ),
        ],
      ),
    );
  }

  // ─── หมุดตัวเรา (User Location Pin) ───
  Widget _buildUserMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ป้ายชื่อ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            _isSimulatedLocation ? 'ตัวคุณ (จำลอง)' : 'ตัวคุณ',
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Pulse Ring & Inner Dot
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                  border: Border.all(
                    color: const Color(0xFF2563EB),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ─── หมุดจุดนัดรับ (Destination Marker) ───
  Widget _buildDestinationMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ป้ายชื่อจุดนัดรับ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: AppColors.primaryColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 11,
                color: Colors.white,
              ),
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 85),
                child: Text(
                  _resolvedLocation,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        // หมุดไอคอนกล่องพัสดุ
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: AppColors.primaryColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryColor.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.inventory_2_rounded,
              color: AppColors.primaryColor,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ─── ปุ่มกลมลอยบนแผนที่ ───
  Widget _buildMapFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color color = Colors.white,
    Color iconColor = const Color(0xFF1E2022),
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF1E2022), size: 20),
        ),
      ),
    );
  }

  // ─── แผงข้อมูลลอยด้านล่าง (Bottom Tracking Card) ───
  Widget _buildTrackingBottomCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ขีดจับลาก
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // 1. หัวแถว: ระยะทาง (อยู่ฝั่งขวา)
              if (_isLoadingRoute) ...[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'กำลังคำนวณเส้นทาง...',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ] else if (_routeResult != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.directions_car_rounded,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _routeResult!.formattedDistance,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // แบนเนอร์แจ้งเตือนกรณี "ยังไม่ถึงวันนัดเช่า"
              if (_isBeforeMeetupDate) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: Color(0xFF64748B),
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'นัดรับอีก $_daysUntilMeetup วัน (${_startDate != null ? DateFormat('d MMM', 'th').format(_startDate!) : ''}) • ชำระเงินเมื่อตรวจรับของจริง',
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // 2. ข้อมูลอุปกรณ์ & จุดนัดรับ
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  children: [
                    // แถวอุปกรณ์
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 52,
                            height: 52,
                            color: const Color(0xFFF1F5F9),
                            child:
                                _resolvedImageUrl != null &&
                                    _resolvedImageUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _resolvedImageUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.grey,
                                      size: 24,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Colors.grey,
                                    size: 24,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _resolvedTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _resolvedPeriod,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_resolvedPrice > 0) ...[
                          Text(
                            '${_resolvedPrice.toStringAsFixed(0)} ฿',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),

                    // แถวจุดนัดรับ
                    InkWell(
                      onTap: _centerToDestination,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _resolvedLocation,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_resolvedLocationNote != null &&
                                    _resolvedLocationNote!.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    _resolvedLocationNote!,
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11.5,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.center_focus_strong_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. ปุ่ม Action (โทร / แชท / นำทาง)
              Row(
                children: [
                  // ปุ่มโทรหาผู้ปล่อยเช่า
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _callOwner,
                      icon: const Icon(Icons.phone_outlined, size: 18),
                      label: Text(
                        _isOwner ? 'โทรหาผู้เช่า' : 'โทรหาเจ้าของ',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ปุ่มชำระเงิน หรือ ส่งมอบอุปกรณ์ หรือ สถานะกำลังเช่า
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentStatusCode == 'active'
                            ? const Color(0xFF0F172A)
                            : (_currentStatusCode == 'cancelled'
                                  ? const Color(0xFF94A3B8)
                                  : AppColors.primaryColor),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _currentStatusCode == 'active'
                          ? null
                          : (_currentStatusCode == 'cancelled'
                                ? null
                                : _openPaymentOrHandover),
                      icon: Icon(
                        _currentStatusCode == 'active'
                            ? Icons.check_circle_rounded
                            : (_currentStatusCode == 'cancelled'
                                  ? Icons.cancel_outlined
                                  : (_isOwner
                                        ? Icons.inventory_2_rounded
                                        : (_renterHandoverStep == 2
                                              ? Icons.qr_code_rounded
                                              : (_renterHandoverStep == 1
                                                    ? Icons.payments_rounded
                                                    : Icons
                                                          .checklist_rounded)))),
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        _currentStatusCode == 'active'
                            ? (_isOwner ? 'กำลังปล่อยเช่า' : 'กำลังเช่าอุปกรณ์')
                            : (_currentStatusCode == 'cancelled'
                                  ? 'ยกเลิกการเช่าแล้ว'
                                  : (_isOwner
                                        ? 'ส่งมอบอุปกรณ์'
                                        : (_renterHandoverStep == 2
                                              ? 'รหัสส่งมอบ'
                                              : (_renterHandoverStep == 1
                                                    ? 'ชำระเงิน'
                                                    : 'ตรวจรับ & ชำระเงิน')))),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
