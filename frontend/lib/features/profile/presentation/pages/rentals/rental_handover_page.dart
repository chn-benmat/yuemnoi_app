import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/models/pickup_location.dart';
import '../../../../../core/services/map_device_position.dart';
import '../../../../../core/widgets/longdo_map_view.dart';
import '../../../../../core/widgets/map_control_button.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/auth_session.dart';
import '../../../../../core/utils/auth_guard.dart';
import '../../../../../core/services/phone_call_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../booking/domain/entities/booking_request_model.dart';
import '../../../../chat/domain/entities/chat_conversation.dart';
import '../../../data/datasources/rental_handover_payment_watcher.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/usecases/update_booking_status_usecase.dart';
import '../../widgets/rentals/rental_pickup_payment_modal.dart';
import '../../../data/datasources/rental_contact_remote_data_source.dart';
import '../../../../chat/data/datasources/chat_remote_data_source.dart';

class RentalHandoverPage extends StatefulWidget {
  final BookingRequestData? bookingData;
  final String? itemTitle;
  final String? itemImageUrl;
  final String? pickupLocation;
  final String? pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;
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
  final RentalContactRemoteDataSource? contactDataSource;
  final PhoneCallService phoneCallService;
  final bool returnToPreviousChat;
  final UpdateBookingStatusUseCase? updateBookingStatusUseCase;

  const RentalHandoverPage({
    super.key,
    this.bookingData,
    this.itemTitle,
    this.itemImageUrl,
    this.pickupLocation,
    this.pickupAddress,
    this.pickupLatitude,
    this.pickupLongitude,
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
    this.contactDataSource,
    this.phoneCallService = const UrlPhoneCallService(),
    this.returnToPreviousChat = false,
    this.updateBookingStatusUseCase,
  });

  @override
  State<RentalHandoverPage> createState() => _RentalHandoverPageState();
}

class _RentalHandoverPageState extends State<RentalHandoverPage> {
  final _map = GlobalKey<LongdoMapViewState>();
  bool _mapReady = false;
  bool _calculatingRoute = false;
  String? _routeDistance;
  LatLng? _routeOrigin;

  LatLng? get _destination {
    final booking = widget.bookingData;
    final returnPoint = widget.returnPoint;
    if (_isReturn)
      return mapPoint(returnPoint?.latitude, returnPoint?.longitude);
    return booking?.pickupCoordinates ??
        mapPoint(widget.pickupLatitude, widget.pickupLongitude);
  }

  Future<void> _showRoute(
    LatLng destination, {
    bool requestPermission = true,
    bool centerOnUser = false,
  }) async {
    if (_calculatingRoute) return;
    setState(() => _calculatingRoute = true);
    try {
      final position = await getMapDevicePosition(
        requestPermission: requestPermission,
      );
      if (!mounted) return;
      final origin = mapPoint(position?.latitude, position?.longitude);
      if (origin == null) {
        if (requestPermission) {
          _showMapMessage('กรุณาอนุญาตให้เข้าถึงตำแหน่งเพื่อแสดงเส้นทาง');
        }
        return;
      }
      _routeOrigin = origin;
      final distance = await _map.currentState?.showRoute(
        origin,
        destination,
        lockMarkers: _isReturn,
      );
      if (mounted && centerOnUser) await _map.currentState?.centerOn(origin);
      if (!mounted) return;
      setState(() => _routeDistance = distance);
      if (distance == null && requestPermission) {
        _showMapMessage('Longdo คำนวณเส้นทางไม่ได้ กรุณาลองอีกครั้ง');
      }
    } catch (_) {
      if (mounted && requestPermission) {
        _showMapMessage('เปิดเส้นทางไม่ได้ กรุณาตรวจสอบ GPS และอินเทอร์เน็ต');
      }
    } finally {
      if (mounted) setState(() => _calculatingRoute = false);
    }
  }

  void _showMapMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ข้อมูลที่ resolve แล้ว
  late String _resolvedTitle;
  late String? _resolvedImageUrl;
  late String _resolvedLocation;
  late String _resolvedPickupDetails;
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
    _resolveInitialData();
    _watchRenterPayment();
  }

  @override
  void dispose() {
    _paymentWatcher?.dispose();
    super.dispose();
  }

  void _resolveInitialData() {
    final b = widget.bookingData;
    final returnPoint = widget.returnPoint;
    _resolvedTitle = b?.item.title ?? widget.itemTitle ?? 'อุปกรณ์เช่า';
    _resolvedImageUrl = b?.item.imageUrl ?? widget.itemImageUrl;
    final location = (returnPoint?.name ?? b?.location ?? widget.pickupLocation)
        ?.trim();
    _resolvedLocation = location?.isNotEmpty == true
        ? location!
        : 'ยังไม่มีข้อมูลจุดนัดหมาย';
    _resolvedPickupDetails =
        (returnPoint?.address ?? b?.locationAddress ?? widget.pickupAddress)
            ?.trim() ??
        '';
    _resolvedPeriod = b != null
        ? b.formattedPeriodSummary
        : (widget.periodText ?? '1 วัน');
    _resolvedPrice = b?.totalPrice ?? widget.totalPrice ?? 0.0;
    _currentStatusCode = widget.statusCode ?? 'confirmed';
    _isOwner = widget.isOwner ?? false;

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
    final point = _destination;
    final hasMap = point != null && LongdoMapView.isAvailable;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 520;
          return Column(
            children: [
              _buildHeader(context, flushMap: hasMap && _isReturn),
              if (hasMap)
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LongdoMapView(
                        key: _map,
                        point: point,
                        showLeftControls: !_isReturn,
                        preferThaiLabels: _isReturn,
                        waitForFirstFrame: _isReturn,
                        collapseAttribution: _isReturn,
                        onReady: (ready) {
                          setState(() => _mapReady = ready);
                          if (ready)
                            unawaited(
                              _showRoute(point, requestPermission: false),
                            );
                        },
                      ),
                      if (_mapReady && !compact)
                        Positioned(
                          right: 16,
                          bottom: 46,
                          child: _buildRouteControls(point),
                        ),
                    ],
                  ),
                )
              else
                const Spacer(),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * (_isReturn ? 0.62 : 0.68),
                ),
                child: _buildTrackingBottomCard(
                  routeControls: hasMap && _mapReady && compact
                      ? _buildRouteControls(point, horizontal: true)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool flushMap}) =>
      SafeArea(
        bottom: !flushMap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, flushMap ? 0 : 8),
          child: Row(
            crossAxisAlignment: flushMap
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center,
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
                          LongdoMapView.isAvailable && _destination != null
                              ? (_isReturn
                                    ? 'เส้นทางคืนสินค้า'
                                    : 'เส้นทางนัดรับอุปกรณ์')
                              : (_isReturn ? 'คืนสินค้า' : 'นัดรับอุปกรณ์'),
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
      );

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
  Widget _buildRouteControls(LatLng point, {bool horizontal = false}) => Flex(
    direction: horizontal ? Axis.horizontal : Axis.vertical,
    mainAxisSize: MainAxisSize.min,
    spacing: 10,
    children: [
      MapControlButton(
        circular: true,
        icon: Icons.crop_free_rounded,
        tooltip: 'ดูภาพรวมเส้นทาง',
        onPressed: () {
          if (_routeDistance != null) {
            _map.currentState?.fitRoute();
          } else {
            _map.currentState?.centerOn(point);
          }
        },
      ),
      MapControlButton(
        circular: true,
        icon: Icons.near_me_rounded,
        tooltip: 'คำนวณเส้นทางด้วย Longdo',
        backgroundColor: const Color(0xFF10B981),
        color: Colors.white,
        onPressed: () => _showRoute(point),
        loading: _calculatingRoute,
      ),
      MapControlButton(
        circular: true,
        icon: Icons.my_location_rounded,
        tooltip: 'ตำแหน่งของฉัน',
        onPressed: _calculatingRoute
            ? null
            : () {
                final origin = _routeOrigin;
                if (origin == null) {
                  unawaited(_showRoute(point, centerOnUser: true));
                } else {
                  _map.currentState?.centerOn(origin);
                }
              },
      ),
    ],
  );

  Widget _buildTrackingBottomCard({Widget? routeControls}) {
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

          if (routeControls != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: routeControls,
              ),
            ),
          if (_routeDistance case final distance?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(8),
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
                        distance,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

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
                Row(
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
                          ),
                          if (_resolvedPickupDetails.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              _resolvedPickupDetails,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // โทรหาคู่เช่าและจัดการการส่งมอบอุปกรณ์
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
      child: SafeArea(top: false, child: SingleChildScrollView(child: content)),
    );
  }
}
