import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/models/pickup_location.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/auth_session.dart';
import '../../../../../core/utils/auth_guard.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/phone_call_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../booking/domain/entities/booking_request_model.dart';
import '../../../../chat/domain/entities/chat_conversation.dart';
import '../../../data/datasources/rental_handover_payment_watcher.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/usecases/update_booking_status_usecase.dart';
import '../../widgets/rentals/rental_pickup_payment_modal.dart';
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
  final DateTime? startDate;
  final bool? isOwner;
  final bool requireBookingId;
  final bool pickupOnly;
  final PickupLocation? returnPoint;
  final Widget? returnDetails;
  final LocationService? locationService;
  final RentalContactRemoteDataSource? contactDataSource;
  final PhoneCallService phoneCallService;
  final bool returnToPreviousChat;
  final UpdateBookingStatusUseCase? updateBookingStatusUseCase;

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
    this.startDate,
    this.isOwner,
    this.requireBookingId = false,
    this.pickupOnly = false,
    this.returnPoint,
    this.returnDetails,
    this.locationService,
    this.contactDataSource,
    this.phoneCallService = const UrlPhoneCallService(),
    this.returnToPreviousChat = false,
    this.updateBookingStatusUseCase,
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
  late final bool _hasDestinationCoordinates;
  DrivingRouteResult? _routeResult;

  bool _isLoadingRoute = true;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isAutoFollow = false;
  late final RentalRouteCubit _routeCubit;
  StreamSubscription<RentalRouteState>? _routeSubscription;

  // ข้อมูลที่ resolve แล้ว
  late String _resolvedTitle;
  late String? _resolvedImageUrl;
  late String _resolvedLocation;
  late String? _resolvedLocationNote;
  late String _resolvedPeriod;
  late double _resolvedPrice;
  late String _currentStatusCode;
  late bool _isOwner;
  int _renterPaymentStep = 0;
  RentalHandoverPaymentWatcher? _paymentWatcher;
  bool _readingPaymentStatus = false;
  late final _updateBookingStatusUseCase =
      widget.updateBookingStatusUseCase ??
      UpdateBookingStatusUseCase(RentalManagementRepositoryImpl());

  bool get _isReturn =>
      widget.returnPoint != null || widget.returnDetails != null;
  bool get _showRentalActions => !_isReturn && !widget.pickupOnly;

  // หน้าจากแชทส่ง ID ใน bookingData ส่วนหน้าสถานะส่ง ID แยก
  int? get _resolvedBookingId =>
      widget.bookingId ?? widget.bookingData?.bookingId;
  String? get _conversationId =>
      widget.conversationId ?? widget.bookingData?.conversationId;
  bool get _canViewBooking =>
      !widget.requireBookingId || AuthSession.isAuthenticated;

  DateTime? get _startDate {
    return widget.bookingData?.startDate ?? widget.startDate;
  }

  bool get _isBeforeMeetupDate {
    final start = _startDate;
    if (start == null) return false;
    return DateTime.now().isBefore(start.toLocal());
  }

  int get _daysUntilMeetup {
    final start = _startDate;
    if (start == null) return 0;
    final now = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    return startDay.difference(today).inDays;
  }

  Future<void> _openPayment() async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_currentStatusCode != 'confirmed') {
      showAppPopup(
        context,
        content: Text(
          _currentStatusCode == 'pending'
              ? 'คำขอเช่ายังรอการยืนยัน จึงยังดำเนินการนัดรับหรือยกเลิกไม่ได้'
              : 'สถานะการเช่านี้ไม่สามารถดำเนินการนัดรับหรือยกเลิกได้',
        ),
      );
      return;
    }

    if (_startDate == null) {
      showAppPopup(
        context,
        content: const Text(
          'ไม่พบเวลานัดเช่าของรายการนี้ กรุณาตรวจสอบรายละเอียดการเช่า',
        ),
      );
      return;
    }

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
                'ยังไม่ถึงเวลาเริ่มเช่า',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            'กำหนดเริ่มเช่า ${_startDate != null ? DateFormat('d MMMM yyyy เวลา HH:mm', 'th').format(_startDate!.toLocal()) : 'ตามที่ตกลง'} น.\n\nระบบจะเปิดให้ตรวจรับอุปกรณ์เมื่อถึงเวลานัด',
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
          ],
        ),
      );
      return;
    }

    _paymentWatcher?.dispose();
    _paymentWatcher = null;
    final status = await RentalPickupPaymentModal.show(
      context,
      bookingId: _resolvedBookingId,
      conversationId: _conversationId,
      itemId: widget.bookingData?.item.id,
      itemTitle: _resolvedTitle,
      totalPrice: _resolvedPrice,
      paymentMethod: widget.bookingData?.paymentMethod ?? 'promptpay',
      initialIsOwner: _isOwner,
      initialStep: _renterPaymentStep,
      updateBookingStatusUseCase: _updateBookingStatusUseCase,
      onStepChanged: (step) {
        if (mounted) {
          setState(() {
            _renterPaymentStep = step;
          });
        }
      },
    );
    if (!mounted) return;
    if (status == null) {
      _watchRenterPayment();
      return;
    }
    await _applyPaymentStatus(status);
  }

  void _watchRenterPayment() {
    final bookingId = _resolvedBookingId;
    if (!_showRentalActions ||
        _isOwner ||
        _currentStatusCode != 'confirmed' ||
        _startDate == null ||
        bookingId == null ||
        bookingId <= 0) {
      return;
    }
    _paymentWatcher = RentalHandoverPaymentWatcher(
      bookingId: bookingId,
      channelName: 'rental_pickup_map_$bookingId',
      onChanged: () => _checkRenterPayment(bookingId),
    );
  }

  Future<void> _checkRenterPayment(int bookingId) async {
    final watcher = _paymentWatcher;
    if (!mounted ||
        watcher == null ||
        _readingPaymentStatus ||
        !_canViewBooking ||
        _isBeforeMeetupDate ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _readingPaymentStatus = true;
    try {
      final payment = await _updateBookingStatusUseCase.handoverPayment(
        bookingId: bookingId,
      );
      if (mounted &&
          identical(_paymentWatcher, watcher) &&
          ModalRoute.of(context)?.isCurrent == true &&
          payment.status != 'confirmed') {
        await _applyPaymentStatus(payment.status);
      }
    } catch (_) {
      // ตรวจสอบใหม่รอบถัดไปเมื่อการเชื่อมต่อสะดุดชั่วคราว
    } finally {
      _readingPaymentStatus = false;
    }
  }

  Future<void> _applyPaymentStatus(String status) async {
    _paymentWatcher?.dispose();
    _paymentWatcher = null;
    setState(() {
      _currentStatusCode = status;
      _renterPaymentStep = 0;
    });
    if (status != 'active') return;

    ChatConversation? conversation;
    if (!widget.returnToPreviousChat) {
      try {
        conversation =
            await (widget.contactDataSource ?? RentalContactRemoteDataSource())
                .getConversation(
                  bookingId: _resolvedBookingId,
                  conversationId: _conversationId,
                );
      } catch (_) {
        // เปิดรายการแชทได้แม้โหลดข้อมูลห้องสนทนาไม่สำเร็จ
      }
    }
    if (!mounted ||
        !_canViewBooking ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    AppRoutes.returnToChatAfterPickup(
      context,
      returnToPreviousChat: widget.returnToPreviousChat,
      conversation: conversation,
    );
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _resolveInitialData();
    _watchRenterPayment();
    if (_hasDestinationCoordinates) _pulseController.repeat(reverse: true);
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
    _paymentWatcher?.dispose();
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _resolveInitialData() {
    final b = widget.bookingData;
    final returnPoint = widget.returnPoint;
    _resolvedTitle = b?.item.title ?? widget.itemTitle ?? 'อุปกรณ์เช่า';
    _resolvedImageUrl = b?.item.imageUrl ?? widget.itemImageUrl;
    _resolvedLocation =
        returnPoint?.name ??
        b?.location ??
        widget.pickupLocation ??
        'สยามพารากอน';
    _resolvedLocationNote =
        returnPoint?.note ?? b?.locationNote ?? widget.pickupNote;
    _resolvedPeriod = b != null
        ? b.formattedPeriodSummary
        : (widget.periodText ?? '1 วัน');
    _resolvedPrice = b?.totalPrice ?? widget.totalPrice ?? 0.0;
    _currentStatusCode = widget.statusCode ?? 'confirmed';
    _isOwner = widget.isOwner ?? false;

    final destLat = _isReturn
        ? returnPoint?.latitude
        : b?.latitude ?? b?.item.latitude ?? widget.destinationLat;
    final destLng = _isReturn
        ? returnPoint?.longitude
        : b?.longitude ?? b?.item.longitude ?? widget.destinationLng;
    _hasDestinationCoordinates =
        destLat != null &&
        destLng != null &&
        destLat.isFinite &&
        destLng.isFinite &&
        destLat.abs() <= 90 &&
        destLng.abs() <= 180;

    if (_hasDestinationCoordinates) {
      _destinationLocation = LatLng(destLat!, destLng!);
    } else {
      final fallback = LocationService.resolveCoordinates(
        locationName: _resolvedLocation,
      );
      _destinationLocation = LatLng(fallback.latitude, fallback.longitude);
    }

    if (_showRentalActions) _loadSavedPaymentStep();
  }

  Future<void> _loadSavedPaymentStep() async {
    final step = await RentalPickupPaymentModal.getSavedStep(
      bookingId: _resolvedBookingId,
      conversationId: _conversationId,
      itemId: widget.bookingData?.item.id,
      itemTitle: _resolvedTitle,
    );
    if (mounted) {
      setState(() {
        _renterPaymentStep = step;
      });
    }
  }

  Future<void> _initLocationsAndRoute() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRoute = _routeResult == null;
    });

    // เริ่มจากพิกัดล่าสุดก่อน ระหว่างรอ GPS ใหม่ที่อาจใช้เวลาหลายวินาที
    Position? lastKnown;
    try {
      lastKnown = await _locationService.getLastKnownPosition();
    } catch (_) {}
    if (!mounted) return;
    if (lastKnown != null) _updateUserPosition(lastKnown);

    // ใช้พิกัดจากอุปกรณ์จริงโดยไม่อนุมานจากระยะห่างจากจุดนัดรับ
    Position? position;
    try {
      position = await _locationService.getCurrentPosition();
    } catch (_) {}

    if (!mounted) return;
    if (position != null) _updateUserPosition(position);

    _startLiveLocationTracking();
    if (position == null && _userLocation == null && mounted) {
      setState(() => _isLoadingRoute = false);
    }
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
          _updateUserPosition,
          onError: (e) {
            debugPrint('Live position stream error: $e');
          },
        );
      }
    } catch (e) {
      debugPrint('Cannot start live position stream: $e');
    }
  }

  void _updateUserPosition(Position pos) {
    if (!mounted) return;
    final shouldFitReturn = _isReturn && _userLocation == null;
    final newGps = LatLng(pos.latitude, pos.longitude);

    // อัปเดตตำแหน่งหมุดทันทีแบบ Real-time
    setState(() => _userLocation = newGps);

    // หากเปิดโหมดติดตามตำแหน่งอัตโนมัติ ให้เลื่อนกล้องตามหมุด
    if (_isAutoFollow) {
      _mapController.move(newGps, _mapController.camera.zoom);
    } else if (shouldFitReturn) {
      _fitBoundsToRoute();
    }

    _routeCubit.updatePosition(newGps);
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
          padding: _isReturn
              ? const EdgeInsets.fromLTRB(44, 80, 64, 54)
              : const EdgeInsets.fromLTRB(48, 100, 48, 300),
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
    final opened = await LocationService.openInExternalMaps(
      _destinationLocation.latitude,
      _destinationLocation.longitude,
    );
    if (!opened && _isReturn && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เปิดแอปแผนที่ไม่สำเร็จ')));
    }
  }

  bool _calling = false;

  Future<void> _callOwner() async {
    if (_calling) return;
    _calling = true;
    try {
      final phone =
          await (widget.contactDataSource ?? RentalContactRemoteDataSource())
              .getPhone(
                bookingId: _resolvedBookingId,
                conversationId: _conversationId,
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

  Widget _buildUnavailableState(String message, {bool showLogin = false}) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จุดนัดรับสินค้า'),
        leading: const BackButton(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
              ),
              if (showLogin) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    final authenticated = await AuthGuard.requireAuth(context);
                    if (authenticated && mounted) setState(() {});
                  },
                  child: const Text('เข้าสู่ระบบ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requireBookingId &&
        _showRentalActions &&
        (_resolvedBookingId == null || _resolvedBookingId! <= 0)) {
      return _buildUnavailableState(
        'ไม่พบรายการเช่านี้ กรุณาเปิดหน้าจากรายการเช่าของคุณ',
      );
    }
    if (widget.requireBookingId && !AuthSession.isAuthenticated) {
      return _buildUnavailableState(
        'กรุณาเข้าสู่ระบบเพื่อดูรายละเอียดนัดรับ',
        showLogin: true,
      );
    }
    if (!_hasDestinationCoordinates) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isReturn ? 'คืนสินค้า' : 'จุดนัดรับสินค้า'),
        ),
        body: _isReturn
            ? _buildTrackingBottomCard()
            : const Center(
                child: Text(
                  'การจองนี้ยังไม่มีพิกัดจุดนัดรับ กรุณาติดต่อคู่เช่า',
                ),
              ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isReturn
          ? LayoutBuilder(
              builder: (context, constraints) {
                final sheetHeight = constraints.maxHeight * 0.62;
                return Column(
                  children: [
                    Expanded(
                      child: _buildMap(
                        context,
                        horizontalControls: constraints.maxHeight < 600,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: sheetHeight),
                      child: _buildTrackingBottomCard(),
                    ),
                  ],
                );
              },
            )
          : _buildMap(context),
    );
  }

  Widget _buildMap(BuildContext context, {bool horizontalControls = false}) {
    return Stack(
      children: [
        // ─── 1. แผนที่ Interactive (FlutterMap) ───
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            onMapReady: _initLocationsAndRoute,
            initialCenter: _destinationLocation,
            initialZoom: 14.5,
            minZoom: _isReturn ? 1 : 4,
            maxZoom: 19,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _isAutoFollow) {
                setState(() {
                  _isAutoFollow = false;
                });
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
                        Expanded(
                          child: Text(
                            _isReturn
                                ? 'เส้นทางคืนสินค้า'
                                : 'เส้นทางนัดรับอุปกรณ์',
                            style: const TextStyle(
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

        Positioned(
          right: 16,
          bottom: _isReturn ? 14 : 310,
          child: Flex(
            direction: horizontalControls ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              _buildMapFloatingButton(
                icon: Icons.crop_free_rounded,
                tooltip: 'ดูภาพรวมเส้นทาง',
                onTap: _isReturn && _userLocation == null
                    ? _centerToDestination
                    : _fitBoundsToRoute,
              ),
              _buildMapFloatingButton(
                icon: Icons.near_me_rounded,
                tooltip: 'นำทางด้วย Google Maps',
                color: const Color(0xFF10B981),
                iconColor: Colors.white,
                onTap: _openExternalNavigation,
              ),
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
        if (!_isReturn)
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildTrackingBottomCard(),
          ),
      ],
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
            'ตัวคุณ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  Widget _buildTrackingBottomCard() {
    final isPromptPay = widget.bookingData?.paymentMethod == 'promptpay';
    final inspectionComplete = _renterPaymentStep == 1;
    final showPaymentIcon = _isOwner || (isPromptPay && inspectionComplete);
    final renterActionLabel = switch ((isPromptPay, inspectionComplete)) {
      (true, false) => 'ตรวจรับ & ชำระเงิน',
      (true, true) => 'ชำระเงิน',
      (false, false) => 'ตรวจรับอุปกรณ์',
      (false, true) => 'ดูสถานะนัดรับ',
    };
    final content = Padding(
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
          if (_hasDestinationCoordinates && _isLoadingRoute) ...[
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'กำลังคำนวณเส้นทาง...',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
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
          ] else if (_hasDestinationCoordinates && _userLocation == null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ยังระบุตำแหน่ง GPS ของเครื่องไม่ได้ จึงยังคำนวณเส้นทางไม่ได้',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _initLocationsAndRoute,
                    child: const Text('ลองอีกครั้ง'),
                  ),
                ],
              ),
            ),
          ],

          // แบนเนอร์แจ้งเตือนกรณี "ยังไม่ถึงวันนัดเช่า"
          if (_isBeforeMeetupDate) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
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
                            _isReturn
                                ? widget.periodText ?? _resolvedPeriod
                                : _resolvedPeriod,
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
                  onTap: _hasDestinationCoordinates
                      ? _centerToDestination
                      : null,
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
                              maxLines: _isReturn ? null : 1,
                              overflow: _isReturn
                                  ? null
                                  : TextOverflow.ellipsis,
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
                                maxLines: _isReturn ? null : 1,
                                overflow: _isReturn
                                    ? null
                                    : TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_hasDestinationCoordinates)
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

          // 4. ปุ่ม Action (โทร / แชท / นำทาง)
          if (_showRentalActions) ...[
            const SizedBox(height: 14),
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
                // ปุ่มชำระเงินหรือแสดงสถานะการเช่า
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
                              : _openPayment),
                    icon: Icon(
                      _currentStatusCode == 'active'
                          ? Icons.check_circle_rounded
                          : (_currentStatusCode == 'cancelled'
                                ? Icons.cancel_outlined
                                : (showPaymentIcon
                                      ? Icons.payments_rounded
                                      : Icons.checklist_rounded)),
                      size: 18,
                      color: Colors.white,
                    ),
                    label: Text(
                      _currentStatusCode == 'active'
                          ? (_isOwner ? 'กำลังปล่อยเช่า' : 'กำลังเช่าอุปกรณ์')
                          : (_currentStatusCode == 'cancelled'
                                ? 'ยกเลิกการเช่าแล้ว'
                                : (_isOwner
                                      ? 'ยืนยันการรับเงิน'
                                      : renterActionLabel)),
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
          if (widget.returnDetails case final details?) ...[
            const SizedBox(height: 12),
            details,
          ],
        ],
      ),
    );

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
        child: _isReturn ? SingleChildScrollView(child: content) : content,
      ),
    );
  }
}
