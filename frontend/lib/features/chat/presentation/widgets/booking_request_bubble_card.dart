import 'dart:async';
import 'chat_cached_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_popup.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';

class BookingRequestBubbleCard extends StatefulWidget {
  const BookingRequestBubbleCard({
    super.key,
    required this.message,
    required this.bookingData,
    this.senderName,
    this.isOwner,
    this.isHandoverCompleted = false,
    this.isReturnCompleted = false,
    this.initialStatus,
    this.onTap,
    this.onRetryCustomerRequest,
    this.customerRequestBlockedByRental = false,
    this.customerRequestAvailabilityPending = false,
    this.onRequestRentalQueue,
  });

  final ChatMessage message;
  final BookingRequestData bookingData;
  final String? senderName;
  final bool? isOwner;
  final bool isHandoverCompleted;
  final bool isReturnCompleted;
  final String? initialStatus;
  final VoidCallback? onTap;
  final VoidCallback? onRetryCustomerRequest;
  final bool customerRequestBlockedByRental;
  final bool customerRequestAvailabilityPending;
  final VoidCallback? onRequestRentalQueue;

  @override
  State<BookingRequestBubbleCard> createState() =>
      _BookingRequestBubbleCardState();
}

class _BookingRequestBubbleCardState extends State<BookingRequestBubbleCard> {
  bool _isConfirmed = false;
  bool _isCheckingBookingStatus = false;
  bool _bookingStatusUnavailable = false;
  int _statusCheckRevision = 0;
  ({int bookingId, String status, VoidCallback open})? _pendingBookingAction;
  int? _bookingId;
  String _paymentMethod = 'cash';
  String _rentalStatus =
      'pending'; // 'pending', 'confirmed', 'active', 'completed'
  DateTime? _endDateTime;
  Timer? _countdownTimer;

  String? get _sharedStatus =>
      widget.bookingData.status ?? widget.initialStatus;

  bool get _hasSharedCancellation =>
      _sharedStatus == 'cancelled' && _rentalStatus == 'cancelled';

  bool get _shouldCheckInitialStatus =>
      _rentalStatus != 'completed' &&
      !_hasSharedCancellation &&
      ((_bookingId ?? 0) > 0 || _isConfirmed) &&
      SupabaseConfig.isInitialized &&
      SupabaseConfig.client.auth.currentUser != null;

  bool get _isRentalActive => const {
    'active',
    'awaiting_return',
    'return_ready',
  }.contains(_rentalStatus);

  /// คำนวณกำหนดคืนจากเวลาเริ่มส่งมอบจริงและระยะเวลาเช่าที่ตกลงไว้
  DateTime get _effectiveEndDateTime {
    final handoverStart = BookingConfirmationTracker.getHandoverStartTimeSync(
      bookingId: _bookingId,
      messageId: widget.message.id,
    );
    var agreedDuration = widget.bookingData.endDateTime.difference(
      widget.bookingData.startDateTime,
    );
    if (agreedDuration <= Duration.zero) {
      final duration = widget.bookingData.duration > 0
          ? widget.bookingData.duration
          : 1;
      agreedDuration = widget.bookingData.rentalType == BookingRentalType.hourly
          ? Duration(hours: duration)
          : Duration(days: duration);
    }

    final initialEnd = _endDateTime ?? widget.bookingData.endDateTime;
    final now = DateTime.now();

    // 1. ถ้ามีเวลาเริ่มส่งมอบจริง (Handover Started) ให้เริ่มนับเวลาเช่าจากช่วงเวลาที่ส่งมอบจริง
    if (handoverStart != null) {
      return handoverStart.add(agreedDuration);
    }

    // 2. ถ้าสถานะเป็น active แต่เวลาสิ้นสุดเดิมอยู่ในอดีตแล้ว (เช่น จองไว้วันก่อนหน้า แล้วเพิ่งใส่ PIN/QR เริ่มยืมวันนี้)
    // ป้องกันการนับเวลาว่าเลทล่วงหน้า 90 ชั่วโมง
    if (_isRentalActive && initialEnd.isBefore(now)) {
      return now.add(agreedDuration);
    }

    return initialEnd;
  }

  @override
  void initState() {
    super.initState();
    _applySharedStatus();
    _isCheckingBookingStatus = _shouldCheckInitialStatus;
    _checkConfirmedStatus();
  }

  void _applySharedStatus() {
    _paymentMethod = widget.bookingData.paymentMethod;
    final status = _sharedStatus;
    // ข้อความเดิมอาจยังเป็น confirmed แม้รายการนี้จะคืนเสร็จแล้ว
    if (status != null && _rentalStatus != 'completed') {
      _rentalStatus = status;
      _isConfirmed = const {
        'confirmed',
        'active',
        'awaiting_return',
        'return_ready',
        'cancelled',
        'completed',
      }.contains(status);
    }
    _bookingId = widget.bookingData.bookingId ?? _bookingId;
    if (_hasSharedCancellation) {
      _isCheckingBookingStatus = false;
      _bookingStatusUnavailable = false;
      _pendingBookingAction = null;
      _countdownTimer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant BookingRequestBubbleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bookingChanged =
        widget.message.id != oldWidget.message.id ||
        (widget.bookingData.bookingId != oldWidget.bookingData.bookingId &&
            widget.bookingData.bookingId != _bookingId);
    if (bookingChanged) {
      _bookingId = null;
      _isConfirmed = false;
      _bookingStatusUnavailable = false;
      _pendingBookingAction = null;
      _rentalStatus = 'pending';
      _endDateTime = null;
      _countdownTimer?.cancel();
    }
    if (bookingChanged ||
        widget.isHandoverCompleted != oldWidget.isHandoverCompleted ||
        widget.isReturnCompleted != oldWidget.isReturnCompleted ||
        widget.initialStatus != oldWidget.initialStatus ||
        widget.bookingData.status != oldWidget.bookingData.status ||
        widget.bookingData.bookingId != oldWidget.bookingData.bookingId ||
        widget.bookingData.paymentMethod !=
            oldWidget.bookingData.paymentMethod) {
      _applySharedStatus();
      if (bookingChanged) _isCheckingBookingStatus = _shouldCheckInitialStatus;
      _checkConfirmedStatus();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  bool get _isExpired => DateTime.now().isAfter(_effectiveEndDateTime);

  String _formatRemainingTime() {
    final now = DateTime.now();
    final difference = _effectiveEndDateTime.difference(now);

    if (difference.isNegative || difference == Duration.zero) {
      return 'ครบกำหนดเวลาคืนแล้ว';
    }

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    final seconds = difference.inSeconds % 60;

    if (days > 0) {
      return '$days วัน $hours ชม. $minutes นาที';
    } else if (hours > 0) {
      return '$hours ชม. $minutes นาที $seconds วินาที';
    } else if (minutes > 0) {
      return '$minutes นาที $seconds วินาที';
    } else {
      return '$seconds วินาที';
    }
  }

  String _formatDeadline(DateTime dt) {
    return DateFormat('dd/MM/yyyy เวลา HH:mm น.').format(dt.toLocal());
  }

  void _retryBookingStatus() {
    setState(() {
      _isCheckingBookingStatus = true;
      _bookingStatusUnavailable = false;
    });
    _checkConfirmedStatus();
  }

  VoidCallback? _bookingAction(VoidCallback open) {
    final bookingId = _bookingId;
    final status = _rentalStatus;
    if (_bookingStatusUnavailable ||
        (_isCheckingBookingStatus && (bookingId ?? 0) <= 0)) {
      return null;
    }
    return () {
      if (_bookingStatusUnavailable ||
          _pendingBookingAction != null ||
          _bookingId != bookingId ||
          _rentalStatus != status) {
        return;
      }
      if (!_isCheckingBookingStatus) {
        open();
        return;
      }
      if (bookingId == null || bookingId <= 0) return;
      setState(() {
        _pendingBookingAction = (
          bookingId: bookingId,
          status: _isRentalActive ? 'active' : status,
          open: open,
        );
      });
    };
  }

  Widget _bookingActionIcon(Widget icon, {Color color = Colors.white}) =>
      _pendingBookingAction == null
      ? icon
      : SizedBox.square(
          dimension: 15,
          child: CircularProgressIndicator(
            color: color,
            strokeWidth: 2,
            semanticsLabel: 'กำลังตรวจสอบสถานะการเช่า',
          ),
        );

  Future<void> _checkConfirmedStatus() async {
    final message = widget.message;
    final revision = ++_statusCheckRevision;
    // สถานะยกเลิกที่มากับข้อความใช้แสดงปุ่มได้ทันที ส่วนการเปิดฟอร์มเช่าเช็กอุปกรณ์อีกครั้ง
    if (_hasSharedCancellation) return;

    bool isCurrentCheck() => mounted && revision == _statusCheckRevision;
    // 1. ตรวจสอบสถานะการยืนยันจาก Local Tracker ทันที (เฉพาะ messageId)
    final isLocallyConfirmed = await BookingConfirmationTracker.isConfirmed(
      messageId: message.id,
    );
    final cachedBookingId = await BookingConfirmationTracker.getBookingId(
      messageId: message.id,
    );
    final cachedStatus = await BookingConfirmationTracker.getStatus(
      messageId: message.id,
    );
    if (!isCurrentCheck()) return;
    final targetBookingId =
        widget.bookingData.bookingId ?? cachedBookingId ?? _bookingId;
    // ข้อความส่งมอบหรือคืนของเก่าในห้องแชตใช้กับคำขอที่ยังไม่มีเลขรายการไม่ได้
    final useLegacyStatus =
        _sharedStatus == null && targetBookingId != null && targetBookingId > 0;

    if (mounted) {
      setState(() {
        if (useLegacyStatus &&
            (isLocallyConfirmed ||
                widget.isHandoverCompleted ||
                widget.isReturnCompleted)) {
          _isConfirmed = true;
        }
        if (widget.bookingData.bookingId == null &&
            cachedBookingId != null &&
            cachedBookingId > 0 &&
            _bookingId != cachedBookingId) {
          _bookingId = cachedBookingId;
          _isCheckingBookingStatus = _shouldCheckInitialStatus;
        }
        if (_rentalStatus == 'completed' ||
            (useLegacyStatus &&
                (cachedStatus == 'completed' || widget.isReturnCompleted))) {
          _rentalStatus = 'completed';
          _countdownTimer?.cancel();
        } else if (useLegacyStatus && widget.isHandoverCompleted) {
          _rentalStatus = 'active';
          _startCountdownTimer();
        } else if (useLegacyStatus &&
            cachedStatus != null &&
            cachedStatus.isNotEmpty) {
          _rentalStatus = cachedStatus;
          if (_isRentalActive) {
            _startCountdownTimer();
          }
        }
      });
    }

    if (widget.isHandoverCompleted && _rentalStatus == 'active') {
      await BookingConfirmationTracker.markActive(messageId: widget.message.id);
    } else if (_rentalStatus == 'completed') {
      await BookingConfirmationTracker.setStatus(
        messageId: widget.message.id,
        status: 'completed',
      );
    }

    // 2. ตรวจสอบสถานะจาก Supabase booking_tb
    // โดยจะตรวจสอบเฉพาะ bookingId ที่ถูกผูกไว้กับข้อความคำขอนี้เท่านั้น (ป้องกันการปะปนกับออเดอร์อื่น)
    try {
      if (!isCurrentCheck() ||
          !SupabaseConfig.isConfigured ||
          !SupabaseConfig.isInitialized) {
        return;
      }
      final client = SupabaseConfig.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (targetBookingId != null && targetBookingId > 0) {
        final exactBooking = await client
            .from('booking_tb')
            .select(
              'id, status, created_at, start_at, end_at, user_id, payment_method',
            )
            .eq('id', targetBookingId)
            .maybeSingle();

        final rawDbStatus = exactBooking?['status']
            ?.toString()
            .toLowerCase()
            .trim();
        if (exactBooking != null &&
            rawDbStatus != null &&
            rawDbStatus.isNotEmpty &&
            isCurrentCheck()) {
          final parsedEndAt = DateTime.tryParse(
            exactBooking['end_at']?.toString() ?? '',
          );
          final databasePaymentMethod = exactBooking['payment_method']
              ?.toString();

          final String resolvedStatus;
          if (rawDbStatus == 'completed' ||
              rawDbStatus == 'finished' ||
              rawDbStatus == 'คืนของสำเร็จ') {
            resolvedStatus = 'completed';
          } else if (rawDbStatus == 'active' ||
              rawDbStatus == 'awaiting_return' ||
              rawDbStatus == 'return_ready' ||
              rawDbStatus == 'กำลังเช่า' ||
              rawDbStatus == 'กำลังใช้งาน') {
            resolvedStatus = 'active';
          } else if (rawDbStatus == 'cancelled') {
            resolvedStatus = 'cancelled';
          } else if (rawDbStatus == 'confirmed') {
            resolvedStatus = useLegacyStatus && widget.isHandoverCompleted
                ? 'active'
                : 'confirmed';
          } else {
            resolvedStatus = 'pending';
          }

          final pendingAction = _pendingBookingAction;
          setState(() {
            _isConfirmed = const {
              'confirmed',
              'active',
              'awaiting_return',
              'return_ready',
              'cancelled',
              'completed',
            }.contains(resolvedStatus);
            _rentalStatus = resolvedStatus;
            _isCheckingBookingStatus = false;
            _bookingStatusUnavailable = false;
            _pendingBookingAction = null;
            _bookingId = targetBookingId;
            if (databasePaymentMethod == 'cash' ||
                databasePaymentMethod == 'promptpay') {
              _paymentMethod = databasePaymentMethod!;
            }
            if (parsedEndAt != null) {
              _endDateTime = parsedEndAt;
            }
            if (_isRentalActive) {
              _startCountdownTimer();
            } else {
              _countdownTimer?.cancel();
            }
          });

          // เปิดเฉพาะรายการที่ผู้ใช้กด และยังอยู่ในสถานะเดียวกันหลังตรวจสอบ
          if (pendingAction != null &&
              pendingAction.bookingId == targetBookingId &&
              pendingAction.status == resolvedStatus &&
              mounted &&
              ModalRoute.isCurrentOf(context) == true) {
            pendingAction.open();
          }

          if (!widget.bookingData.isCustomerRequest ||
              resolvedStatus != 'pending') {
            await BookingConfirmationTracker.markConfirmed(
              messageId: widget.message.id,
              bookingId: targetBookingId,
            );
          }
          await BookingConfirmationTracker.setStatus(
            messageId: message.id,
            status: resolvedStatus,
          );
        }
      } else if (mounted &&
          !_isConfirmed &&
          !isLocallyConfirmed &&
          !widget.isHandoverCompleted &&
          !widget.isReturnCompleted) {
        // หากยังไม่มีการยืนยันคำขอนี้ ให้คงสถานะคำขอใหม่ (pending) แยกกระบวนการชัดเจน ไม่ปะปนกับออเดอร์เก่า
        setState(() {
          _isConfirmed = false;
          _rentalStatus = 'pending';
          _bookingId = null;
        });
      }
    } catch (_) {
      if (isCurrentCheck() &&
          !widget.bookingData.isCustomerRequest &&
          !_isConfirmed &&
          !isLocallyConfirmed &&
          !widget.isHandoverCompleted &&
          !widget.isReturnCompleted) {
        setState(() {
          _isConfirmed = false;
          _rentalStatus = 'pending';
          _bookingId = null;
        });
      }
    } finally {
      if (isCurrentCheck() && _isCheckingBookingStatus) {
        setState(() {
          _isCheckingBookingStatus = false;
          _bookingStatusUnavailable = (targetBookingId ?? 0) > 0;
          _pendingBookingAction = null;
        });
      }
    }
  }

  bool _checkIsOwner() {
    if (widget.isOwner != null) return widget.isOwner!;
    return widget.message.isMine != widget.bookingData.isCustomerRequest;
  }

  bool get _canConfirmCustomerRequest =>
      _checkIsOwner() && !widget.message.isMine && _isPendingCustomerRequest;

  bool get _canEditCustomerRequest =>
      !_checkIsOwner() && widget.message.isMine && _isPendingCustomerRequest;

  bool get _isPendingCustomerRequest =>
      widget.bookingData.isCustomerRequest &&
      !widget.customerRequestBlockedByRental &&
      !widget.customerRequestAvailabilityPending &&
      _rentalStatus == 'pending' &&
      (_bookingId ?? 0) > 0 &&
      !widget.bookingData.hasCustomerRequestStartPassed;

  void _openMeetupLocation(BuildContext context) {
    final bookingData = widget.bookingData;
    final isOwner = _checkIsOwner();
    final bookingId = _bookingId ?? bookingData.bookingId;
    AppRoutes.openRentalHandover(
      context,
      isOwner: isOwner,
      startDate: bookingData.startDate,
      pickupOnly:
          bookingId == null ||
          bookingId <= 0 ||
          (bookingData.isCustomerRequest && !_isConfirmed),
      trackingArgs: {
        'itemTitle': bookingData.item.title,
        'itemImageUrl': bookingData.item.imageUrl,
        'pickupLocation': bookingData.location.trim().isNotEmpty
            ? bookingData.location
            : bookingData.item.defaultLocation,
        'pickupAddress': bookingData.locationAddress,
        'pickupLatitude': bookingData.pickupCoordinates?.latitude,
        'pickupLongitude': bookingData.pickupCoordinates?.longitude,
        'ownerName': bookingData.item.ownerName,
        'periodText': bookingData.formattedPeriodSummary,
        'totalPrice': bookingData.totalPrice,
        'statusCode': _rentalStatus,
        'bookingId': bookingId,
        'conversationId':
            bookingData.conversationId ?? widget.message.conversationId,
        'isOwner': isOwner,
      },
    );
  }

  Future<void> _handleAction(
    BuildContext context, {
    required bool isEditMode,
  }) async {
    final isOwner = _checkIsOwner();
    final attachedData = widget.bookingData.copyWith(
      bookingId: _bookingId,
      paymentMethod: _paymentMethod,
      originalMessageId: widget.message.id,
      conversationId:
          widget.bookingData.conversationId ?? widget.message.conversationId,
    );

    if (_isConfirmed) {
      AppRoutes.openRentalHandover(
        context,
        bookingData: attachedData,
        isOwner: isOwner,
        trackingArgs: {
          'bookingId': _bookingId,
          'conversationId': attachedData.conversationId,
        },
      );
      return;
    }

    if (isEditMode) {
      if (attachedData.isCustomerRequest
          ? !_canEditCustomerRequest
          : !isOwner) {
        return;
      }
      final isQueueOffer =
          !attachedData.isCustomerRequest &&
          attachedData.rentalQueueMessageId != null;
      if (isQueueOffer && attachedData.bookingId != null) {
        showAppPopup(
          context,
          content: const Text(
            'ข้อเสนอนี้ผูกกับรายการเช่าแล้ว จึงแก้ไขเวลานัดรับไม่ได้',
          ),
        );
        return;
      }
      AppRoutes.openBooking(
        context,
        initialData: attachedData,
        isEditMode: true,
        originalQueueOfferMessage: isQueueOffer ? widget.message.message : null,
      );
      return;
    }

    if (attachedData.isCustomerRequest && !_canConfirmCustomerRequest) return;
    final confirmed = await AppRoutes.openBookingConfirmation(
      context,
      bookingData: attachedData,
    );
    if (confirmed == true ||
        (!attachedData.isCustomerRequest &&
            await BookingConfirmationTracker.isConfirmed(
              messageId: widget.message.id,
            ))) {
      final int? updatedBookingId =
          await BookingConfirmationTracker.getBookingId(
            messageId: widget.message.id,
          );
      if (mounted) {
        setState(() {
          _isConfirmed = true;
          if (_rentalStatus == 'pending' && confirmed == true) {
            _rentalStatus = 'confirmed';
          }
          if (updatedBookingId != null && updatedBookingId > 0) {
            _bookingId = updatedBookingId;
          }
        });
      }
      await _checkConfirmedStatus();
    } else {
      _checkConfirmedStatus();
    }
  }

  String _formatPrice(double price) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(price)} ฿';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.message.isMine;
    final item = widget.bookingData.item;
    final displayImageUrl =
        (widget.message.imageUrl != null && widget.message.imageUrl!.isNotEmpty)
        ? widget.message.imageUrl!
        : item.imageUrl;
    final isOwnerUser = _checkIsOwner();
    final String? bookingStatusMessage = _rentalStatus == 'completed'
        ? null
        : _isCheckingBookingStatus
        ? 'กำลังตรวจสอบสถานะการเช่า…'
        : _bookingStatusUnavailable
        ? 'ตรวจสอบสถานะการเช่าไม่สำเร็จ'
        : null;
    final canUseBookingActions = bookingStatusMessage == null;
    // แสดงสถานะจากข้อความเดิมได้ระหว่างรอตรวจสอบสถานะล่าสุด
    final canShowStatus = canUseBookingActions || _sharedStatus != null;
    final showActiveStatus = canShowStatus && _isRentalActive;

    final senderText =
        (widget.senderName != null && widget.senderName!.isNotEmpty)
        ? widget.senderName!
        : (item.ownerName.isNotEmpty ? item.ownerName : 'ผู้เช่า');

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. ภาพขนาดใหญ่ พร้อมป้ายชื่อสินค้าแบบ Swiss Minimal
            GestureDetector(
              onTap: () {
                if (displayImageUrl.isNotEmpty) {
                  ChatCachedImage.openFullScreen(
                    context,
                    imageUrls: [displayImageUrl],
                    initialIndex: 0,
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 210,
                      color: const Color(0xFFF1F5F9),
                      child: displayImageUrl.isNotEmpty
                          ? ChatCachedImage(
                              imageUrl: displayImageUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              placeholder: (_, _) => const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => const Icon(
                                Icons.image_not_supported_outlined,
                                color: Color(0xFF94A3B8),
                                size: 36,
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: Color(0xFF94A3B8),
                                size: 40,
                              ),
                            ),
                    ),

                    // ป้ายชื่ออุปกรณ์โปร่งแสงที่มุมซ้ายล่าง
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ป้ายเลขออเดอร์ที่มุมขวาบน
                    if (_bookingId != null && _bookingId! > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.receipt_long_rounded,
                                size: 12,
                                color: Color(0xFF34D399),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '#${BookingConfirmationTracker.formatOrderNumber(_bookingId)}',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
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

            const SizedBox(height: 10),

            // 2. ข้อความรายละเอียดแบบ Minimal
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canShowStatus
                        ? _getCardTitle(isMine, senderText)
                        : 'รายละเอียดคำขอเช่า',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canShowStatus ? _getCardSubtitle() : bookingStatusMessage,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: showActiveStatus
                          ? AppColors.primaryColor
                          : const Color(0xFF64748B),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                key: const ValueKey('chat-booking-item-detail-button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  side: const BorderSide(color: Color(0xFFD8B4FE), width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () =>
                    AppRoutes.openItemDetail(context, itemId: item.id),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text(
                  'ดูรายละเอียดสินค้า',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // 3. กล่องข้อมูลการเช่าแบบ Swiss Table (แสดงเฉพาะก่อนเริ่มการเช่า)
            if (!showActiveStatus) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (_bookingId != null && _bookingId! > 0) ...[
                      _buildMiniInfoRow(
                        label: 'เลขออเดอร์',
                        value:
                            '#${BookingConfirmationTracker.formatOrderNumber(_bookingId)}',
                      ),
                      const SizedBox(height: 7),
                    ],
                    _buildMiniInfoRow(
                      label: 'เวลาเช่า',
                      value: widget.bookingData.formattedDetailedRentalPeriod,
                    ),
                    const SizedBox(height: 7),
                    _buildMiniInfoRow(
                      label: 'จุดนัดพบ',
                      value: widget.bookingData.location,
                      showLinkIcon: true,
                      onTap: () => _openMeetupLocation(context),
                    ),
                    const SizedBox(height: 7),
                    _buildMiniInfoRow(
                      label: 'การชำระเงิน',
                      value: _paymentMethod == 'promptpay'
                          ? 'พร้อมเพย์ (ชำระเมื่อรับของ)'
                          : 'เงินสด (ชำระเมื่อรับของ)',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),
                    _buildMiniInfoRow(
                      label: 'ยอดรวม',
                      value: _formatPrice(widget.bookingData.totalPrice),
                      isPrice: true,
                    ),
                  ],
                ),
              ),
            ],

            // 4. แถบนับเวลาถอยหลังและสถานะเมื่อกำลังเช่าอยู่
            if (showActiveStatus) _buildActiveCountdownCard(),

            const SizedBox(height: 12),

            // 5. ปุ่ม Action
            if (!canShowStatus)
              const SizedBox.shrink()
            else if (showActiveStatus)
              // ปุ่มส่งคืนอุปกรณ์ (หรือตรวจรับคืน)
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  key: const ValueKey('chat-booking-return-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isExpired
                        ? const Color(0xFFDC2626)
                        : (isOwnerUser
                              ? const Color(0xFF10B981)
                              : AppColors.primaryColor),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _bookingAction(
                    () => AppRoutes.openRentalReturn(
                      context,
                      rentalId: _bookingId,
                      isLender: _checkIsOwner(),
                    ),
                  ),
                  icon: _bookingActionIcon(
                    FaIcon(
                      isOwnerUser
                          ? FontAwesomeIcons.qrcode
                          : FontAwesomeIcons.arrowRotateLeft,
                      size: 14,
                    ),
                  ),
                  label: Text(
                    isOwnerUser
                        ? (_isExpired
                              ? 'ตรวจรับคืนอุปกรณ์ทันที (ครบกำหนด)'
                              : 'ตรวจรับคืนอุปกรณ์ & ตรวจสภาพ')
                        : (_isExpired
                              ? 'ส่งคืนอุปกรณ์ทันที (ครบกำหนด)'
                              : 'ส่งคืนอุปกรณ์'),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (_rentalStatus == 'cancelled')
              const Text(
                'ยกเลิกการเช่าแล้ว',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              )
            else if (_rentalStatus == 'completed')
              Container(
                width: double.infinity,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.circleCheck,
                      size: 15,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'การเช่าเสร็จสิ้น',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_isConfirmed)
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  key: const ValueKey('chat-booking-action-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _bookingAction(
                    () => _handleAction(context, isEditMode: false),
                  ),
                  icon: _bookingActionIcon(
                    const FaIcon(FontAwesomeIcons.calendarCheck, size: 14),
                  ),
                  label: const Text(
                    'รายละเอียดนัดรับ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else if (widget.bookingData.isCustomerRequest &&
                !_canConfirmCustomerRequest &&
                !_canEditCustomerRequest)
              const SizedBox.shrink()
            else if (_canEditCustomerRequest || (isMine && isOwnerUser))
              // ผู้ส่งคำขอ/ข้อเสนอ -> สามารถกดแก้ไขรายละเอียดได้
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  key: const ValueKey('chat-booking-action-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _bookingAction(
                    () => _handleAction(context, isEditMode: true),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _bookingActionIcon(
                        const Icon(Icons.edit_outlined, size: 15),
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'แก้ไขรายละเอียด',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // ผู้รับคำขอ/ข้อเสนอ:
              // - หากฉันเป็นเจ้าของอุปกรณ์ (ผู้ปล่อยเช่า): ตรวจสอบและยอมรับคำขอเช่า
              // - หากฉันเป็นผู้เช่า: ตรวจสอบคำขอเช่า / ยืนยันข้อเสนอ
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  key: const ValueKey('chat-booking-action-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _bookingAction(
                    () => _handleAction(context, isEditMode: false),
                  ),
                  icon: _bookingActionIcon(
                    const Icon(Icons.assignment_turned_in_outlined, size: 16),
                  ),
                  label: Text(
                    widget.bookingData.isCustomerRequest
                        ? 'ตรวจสอบและยืนยันคำขอเช่า'
                        : isOwnerUser
                        ? 'ตรวจสอบและยอมรับคำขอเช่า'
                        : 'ตรวจสอบคำขอเช่า',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (canUseBookingActions &&
                widget.onRequestRentalQueue != null &&
                (_rentalStatus == 'pending' ||
                    const {
                      'cancelled',
                      'expired',
                      'rejected',
                    }.contains(_rentalStatus)))
              FilledButton(
                onPressed: widget.onRequestRentalQueue,
                child: const Text('ชวนเข้าคิวเช่าต่อ'),
              )
            else if (canUseBookingActions &&
                (!widget.customerRequestBlockedByRental ||
                    widget.customerRequestAvailabilityPending) &&
                widget.onRetryCustomerRequest != null &&
                (const {
                      'cancelled',
                      'expired',
                      'rejected',
                    }.contains(_rentalStatus) ||
                    (_rentalStatus == 'pending' &&
                        widget.bookingData.hasCustomerRequestStartPassed)))
              TextButton(
                onPressed: widget.customerRequestAvailabilityPending
                    ? null
                    : widget.onRetryCustomerRequest,
                child: const Text('ส่งคำขอเช่าใหม่'),
              ),
            if (bookingStatusMessage != null && _bookingStatusUnavailable) ...[
              if (canShowStatus)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    bookingStatusMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
              OutlinedButton(
                onPressed: _retryBookingStatus,
                child: const Text('ลองตรวจสอบอีกครั้ง'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCountdownCard() {
    final isExpired = _isExpired;
    final remainingText = _formatRemainingTime();
    final accentColor = isExpired
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    final bgColor = isExpired
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFF0FDF4);
    final borderColor = isExpired
        ? const Color(0xFFFECACA)
        : const Color(0xFFBBF7D0);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(
                isExpired
                    ? FontAwesomeIcons.triangleExclamation
                    : FontAwesomeIcons.stopwatch,
                size: 13,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isExpired
                      ? 'ถึงกำหนดส่งคืนอุปกรณ์แล้ว'
                      : 'ระยะเวลาการเช่าที่เหลือ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            remainingText,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ครบกำหนดส่งคืน: ${_formatDeadline(_effectiveEndDateTime)}',
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  String _getCardTitle(bool isMine, String senderText) {
    if (_isRentalActive) {
      final isOwnerUser = _checkIsOwner();
      return isOwnerUser
          ? 'กำลังปล่อยเช่า • อุปกรณ์อยู่ในระหว่างการเช่า'
          : 'ทำการเช่าแล้ว • กำลังใช้งานอุปกรณ์';
    }
    if (_rentalStatus == 'completed') {
      return 'การเช่าเสร็จสิ้นเรียบร้อยแล้ว';
    }
    if (_rentalStatus == 'confirmed') {
      return 'ยืนยันคำขอเช่าเรียบร้อยแล้ว';
    }
    return 'รายละเอียดคำขอเช่า';
  }

  String _getCardSubtitle() {
    if (_isRentalActive) {
      return _isExpired
          ? 'ถึงกำหนดส่งคืนอุปกรณ์แล้ว กรุณาส่งคืนตามจุดนัดพบ'
          : 'เริ่มต้นช่วงเวลาเช่าแล้ว สามารถส่งคืนได้เมื่อครบกำหนด';
    }
    if (_rentalStatus == 'completed') {
      return 'ส่งคืนและตรวจสอบสภาพอุปกรณ์เรียบร้อยแล้ว';
    }
    if (_rentalStatus == 'confirmed') {
      return 'ยืนยันเรียบร้อยแล้ว รอนัดรับและส่งมอบอุปกรณ์';
    }
    if (widget.bookingData.isCustomerRequest && _rentalStatus == 'pending') {
      if (widget.bookingData.hasCustomerRequestStartPassed) {
        return 'เวลานัดรับผ่านไปแล้ว';
      }
      return _checkIsOwner()
          ? 'ลูกค้าส่งคำขอเช่าให้คุณตรวจสอบ'
          : 'รอผู้ปล่อยเช่ายืนยันคำขอ';
    }
    return 'ตรวจสอบข้อมูลและรายละเอียดยืนยันการนัดรับ';
  }

  Widget _buildMiniInfoRow({
    required String label,
    required String value,
    bool isPrice = false,
    bool showLinkIcon = false,
    VoidCallback? onTap,
    int maxLines = 1,
  }) {
    final row = Row(
      crossAxisAlignment: maxLines > 1
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: isPrice ? 14 : 12,
                    fontWeight: isPrice ? FontWeight.w800 : FontWeight.w600,
                    color: isPrice
                        ? AppColors.primaryColor
                        : const Color(0xFF0F172A),
                  ),
                ),
              ),
              if (showLinkIcon) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 12,
                  color: Color(0xFF64748B),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: row,
        ),
      );
    }

    return row;
  }
}
