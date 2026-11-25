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
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../../profile/presentation/widgets/rentals/rental_status_widgets.dart';

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
  });

  final ChatMessage message;
  final BookingRequestData bookingData;
  final String? senderName;
  final bool? isOwner;
  final bool isHandoverCompleted;
  final bool isReturnCompleted;
  final String? initialStatus;
  final VoidCallback? onTap;

  @override
  State<BookingRequestBubbleCard> createState() =>
      _BookingRequestBubbleCardState();
}

class _BookingRequestBubbleCardState extends State<BookingRequestBubbleCard> {
  bool _isConfirmed = false;
  int? _bookingId;
  String _paymentMethod = 'cash';
  String _rentalStatus =
      'pending'; // 'pending', 'confirmed', 'active', 'completed'
  DateTime? _endDateTime;
  Timer? _countdownTimer;

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
    _paymentMethod = widget.bookingData.paymentMethod;
    _applySharedStatus();
    _checkConfirmedStatus();
  }

  void _applySharedStatus() {
    _paymentMethod = widget.bookingData.paymentMethod;
    final status = widget.bookingData.status ?? widget.initialStatus;
    if (status != null) {
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
  }

  @override
  void didUpdateWidget(covariant BookingRequestBubbleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHandoverCompleted != oldWidget.isHandoverCompleted ||
        widget.isReturnCompleted != oldWidget.isReturnCompleted ||
        widget.message != oldWidget.message ||
        widget.initialStatus != oldWidget.initialStatus ||
        widget.bookingData.status != oldWidget.bookingData.status ||
        widget.bookingData.bookingId != oldWidget.bookingData.bookingId ||
        widget.bookingData.paymentMethod !=
            oldWidget.bookingData.paymentMethod) {
      _applySharedStatus();
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
    return DateFormat('dd/MM/yyyy เวลา HH:mm น.').format(dt);
  }

  Future<void> _checkConfirmedStatus() async {
    // 1. ตรวจสอบสถานะการยืนยันจาก Local Tracker ทันที (เฉพาะ messageId)
    final isLocallyConfirmed = await BookingConfirmationTracker.isConfirmed(
      messageId: widget.message.id,
    );
    final cachedBookingId = await BookingConfirmationTracker.getBookingId(
      messageId: widget.message.id,
    );
    final cachedStatus = await BookingConfirmationTracker.getStatus(
      messageId: widget.message.id,
    );
    final targetBookingId =
        widget.bookingData.bookingId ?? cachedBookingId ?? _bookingId;
    final hasSharedStatus =
        widget.bookingData.status != null || widget.initialStatus != null;
    // ข้อความส่งมอบหรือคืนของเก่าในห้องแชตใช้กับคำขอที่ยังไม่มีเลขรายการไม่ได้
    final useLegacyStatus =
        !hasSharedStatus && targetBookingId != null && targetBookingId > 0;

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
            cachedBookingId > 0) {
          _bookingId = cachedBookingId;
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
      if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized) return;
      final client = SupabaseConfig.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (targetBookingId != null && targetBookingId > 0) {
        final exactBooking = await client
            .from('booking_tb')
            .select(
              'id, status, created_at, start_at, end_at, start_date, end_date, user_id, payment_method',
            )
            .eq('id', targetBookingId)
            .maybeSingle();

        if (exactBooking != null && mounted) {
          final rawDbStatus =
              exactBooking['status']?.toString().toLowerCase().trim() ??
              'confirmed';
          final DateTime? parsedEndAt;
          if (exactBooking['end_at'] != null) {
            parsedEndAt = DateTime.tryParse(exactBooking['end_at'].toString());
          } else if (exactBooking['end_date'] != null) {
            parsedEndAt = DateTime.tryParse(
              exactBooking['end_date'].toString(),
            );
          } else {
            parsedEndAt = null;
          }
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

          await BookingConfirmationTracker.markConfirmed(
            messageId: widget.message.id,
            bookingId: targetBookingId,
          );
          await BookingConfirmationTracker.setStatus(
            messageId: widget.message.id,
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
      if (mounted &&
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
    }
  }

  bool _checkIsOwner() {
    if (widget.isOwner != null) return widget.isOwner!;
    return widget.message.isMine;
  }

  void _openMeetupLocation(BuildContext context) {
    final bookingData = widget.bookingData;
    final isOwner = _checkIsOwner();
    final bookingId = _bookingId ?? bookingData.bookingId;
    AppRoutes.openRentalTrackingMap(
      context,
      isOwner: isOwner,
      pickupOnly: bookingId == null || bookingId <= 0,
      trackingArgs: {
        'itemTitle': bookingData.item.title,
        'itemImageUrl': bookingData.item.imageUrl,
        // พิกัดในข้อมูลอุปกรณ์เป็นจุดที่เจ้าของเลือกไว้ตอนลงประกาศ
        'pickupLocation': bookingData.item.defaultLocation.isNotEmpty
            ? bookingData.item.defaultLocation
            : bookingData.location,
        'destinationLat': bookingData.item.latitude ?? bookingData.latitude,
        'destinationLng': bookingData.item.longitude ?? bookingData.longitude,
        'pickupNote': bookingData.locationNote,
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

    // ผู้เช่าดูรายละเอียดนัดรับก่อน ส่วนผู้ปล่อยเช่าหรือรายการที่เริ่มเช่าแล้วเปิดแผนที่ได้เลย
    if (_isConfirmed) {
      if (!isOwner && _rentalStatus == 'confirmed') {
        await AppRoutes.openBookingConfirmation(
          context,
          bookingData: attachedData,
          isDetailView: true,
        );
        return;
      }
      AppRoutes.openRentalTrackingMap(
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
      if (!isOwner) return;
      AppRoutes.openBooking(
        context,
        initialData: attachedData,
        isEditMode: true,
      );
      return;
    }

    final confirmed = await AppRoutes.openBookingConfirmation(
      context,
      bookingData: attachedData,
    );
    if (confirmed == true ||
        await BookingConfirmationTracker.isConfirmed(
          messageId: widget.message.id,
        )) {
      final int? updatedBookingId =
          await BookingConfirmationTracker.getBookingId(
            messageId: widget.message.id,
          );
      if (mounted) {
        setState(() {
          _isConfirmed = true;
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
                    _getCardTitle(isMine, senderText),
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
                    _getCardSubtitle(),
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _isRentalActive
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
            if (!_isRentalActive) ...[
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
            if (_isRentalActive) _buildActiveCountdownCard(),

            const SizedBox(height: 12),

            // 5. ปุ่ม Action
            if (_isRentalActive) ...[
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
                  onPressed: () {
                    AppRoutes.openRentalReturn(
                      context,
                      rentalId: _bookingId,
                      isLender: isOwnerUser,
                    );
                  },
                  icon: FaIcon(
                    isOwnerUser
                        ? FontAwesomeIcons.qrcode
                        : FontAwesomeIcons.arrowRotateLeft,
                    size: 14,
                    color: Colors.white,
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
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ปุ่มดูสถานะการเช่า (เปิดหน้า RentalStatusScreen)
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton.icon(
                  key: const ValueKey('chat-booking-rental-status-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => AppRoutes.openRentalStatus(
                    context,
                    isLender: isOwnerUser,
                  ),
                  icon: const FaIcon(
                    FontAwesomeIcons.receipt,
                    size: 13,
                    color: Color(0xFF475569),
                  ),
                  label: Text(
                    isOwnerUser
                        ? 'ดูสถานะปล่อยเช่า (กำลังเช่า / กำลังใช้ของ)'
                        : 'ดูสถานะการเช่า (กำลังเช่า / กำลังใช้ของ)',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ลิงก์ดูจุดนัดพบ / นัดส่งคืนบนแผนที่
              Center(
                child: TextButton.icon(
                  onPressed: () => _handleAction(context, isEditMode: false),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                  icon: const FaIcon(
                    FontAwesomeIcons.locationDot,
                    size: 12,
                    color: Color(0xFF64748B),
                  ),
                  label: const Text(
                    'ดูจุดนัดส่งคืนบนแผนที่',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ] else if (_rentalStatus == 'cancelled') ...[
              OutlinedButton(
                onPressed: () =>
                    AppRoutes.openRentalStatus(context, isLender: isOwnerUser),
                child: Text(
                  isOwnerUser
                      ? 'ยกเลิกการเช่าแล้ว • ดูสถานะปล่อยเช่า'
                      : 'ยกเลิกการเช่าแล้ว • ดูสถานะการเช่า',
                ),
              ),
            ] else if (_rentalStatus == 'completed') ...[
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  key: const ValueKey('chat-booking-rental-status-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => RentalStatusCard.showDetails(
                    context,
                    RentalStatusItemData(
                      bookingId: _bookingId,
                      itemId: item.id,
                      title: item.title,
                      ownerName: widget.senderName ?? item.ownerName,
                      partnerRole: isOwnerUser ? 'ผู้เช่า' : 'เจ้าของอุปกรณ์',
                      status: 'เสร็จสิ้น',
                      statusCode: 'completed',
                      statusColor: const Color(0xFF475569),
                      iconData: Icons.inventory_2_outlined,
                      imageUrl: displayImageUrl,
                      startDate: widget.bookingData.startDateTime,
                      endDate: widget.bookingData.endDateTime,
                      duration:
                          '${widget.bookingData.duration} ${widget.bookingData.rentalType.unit}',
                      totalPrice: widget.bookingData.totalPrice.round(),
                      pickupLocation: widget.bookingData.location,
                      isOwner: isOwnerUser,
                    ),
                  ),
                  icon: const FaIcon(
                    FontAwesomeIcons.circleCheck,
                    size: 15,
                    color: Colors.white,
                  ),
                  label: Text(
                    'การเช่าเสร็จสิ้น',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ] else if (_isConfirmed) ...[
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
                  onPressed: () => _handleAction(context, isEditMode: false),
                  icon: const FaIcon(
                    FontAwesomeIcons.calendarCheck,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'รายละเอียดนัดรับ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  key: const ValueKey('chat-booking-rental-status-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => AppRoutes.openRentalStatus(
                    context,
                    isLender: isOwnerUser,
                  ),
                  icon: const FaIcon(
                    FontAwesomeIcons.receipt,
                    size: 12,
                    color: Color(0xFF475569),
                  ),
                  label: Text(
                    isOwnerUser ? 'ดูสถานะปล่อยเช่า' : 'ดูสถานะการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ] else if (isMine && isOwnerUser)
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
                  onPressed: () => _handleAction(context, isEditMode: true),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: AppColors.primaryColor,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'แก้ไขรายละเอียด',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryColor,
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
                  onPressed: () => _handleAction(context, isEditMode: false),
                  icon: const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    isOwnerUser
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
