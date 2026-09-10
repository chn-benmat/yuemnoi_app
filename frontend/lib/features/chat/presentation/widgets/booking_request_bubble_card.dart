import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';
import '../../domain/entities/chat_message.dart';

class BookingRequestBubbleCard extends StatefulWidget {
  const BookingRequestBubbleCard({
    super.key,
    required this.message,
    required this.bookingData,
    this.senderName,
    this.isOwner,
    this.onTap,
  });

  final ChatMessage message;
  final BookingRequestData bookingData;
  final String? senderName;
  final bool? isOwner;
  final VoidCallback? onTap;

  @override
  State<BookingRequestBubbleCard> createState() =>
      _BookingRequestBubbleCardState();
}

class _BookingRequestBubbleCardState extends State<BookingRequestBubbleCard> {
  bool _isConfirmed = false;
  int? _bookingId;

  @override
  void initState() {
    super.initState();
    _checkConfirmedStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkConfirmedStatus();
  }

  @override
  void didUpdateWidget(covariant BookingRequestBubbleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkConfirmedStatus();
  }

  Future<void> _checkConfirmedStatus() async {
    // 1. ตรวจสอบสถานะการยืนยันจาก Local Tracker ทันที (เฉพาะ messageId)
    final isLocallyConfirmed = await BookingConfirmationTracker.isConfirmed(
      messageId: widget.message.id,
    );
    final cachedBookingId = await BookingConfirmationTracker.getBookingId(
      messageId: widget.message.id,
    );
    if (isLocallyConfirmed) {
      if (mounted) {
        setState(() {
          _isConfirmed = true;
          if (cachedBookingId != null && cachedBookingId > 0) {
            _bookingId = cachedBookingId;
          }
        });
      }
    }

    // 2. ตรวจสอบสถานะจาก Supabase booking_tb
    try {
      if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized) return;
      final client = SupabaseConfig.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final itemId = widget.bookingData.item.id;
      final msgCreatedAt = widget.message.createdAt;
      final minCreatedAt = msgCreatedAt
          .subtract(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String();

      final isOwner = _checkIsOwner();
      var query = client
          .from('booking_tb')
          .select('id, status, created_at')
          .eq('item_id', itemId)
          .gte('created_at', minCreatedAt)
          .inFilter('status', ['pending', 'confirmed', 'active', 'completed']);

      if (!isOwner) {
        query = query.eq('user_id', currentUserId);
      }

      final res = await query.limit(1);

      if (mounted) {
        if (res.isNotEmpty) {
          final foundBookingId = (res.first['id'] as num?)?.toInt();
          setState(() {
            _isConfirmed = true;
            if (foundBookingId != null && foundBookingId > 0) {
              _bookingId = foundBookingId;
            }
          });
          await BookingConfirmationTracker.markConfirmed(
            messageId: widget.message.id,
            bookingId: foundBookingId,
          );
        } else if (!isLocallyConfirmed) {
          setState(() {
            _isConfirmed = false;
          });
        }
      }
    } catch (_) {
      if (mounted && !isLocallyConfirmed) {
        setState(() {
          _isConfirmed = false;
        });
      }
    }
  }

  bool _checkIsOwner() {
    if (widget.isOwner != null) return widget.isOwner!;
    return widget.message.isMine;
  }

  Future<void> _handleAction(BuildContext context, bool isOwner) async {
    final attachedData = widget.bookingData.copyWith(
      originalMessageId: widget.message.id,
      conversationId:
          widget.bookingData.conversationId ?? widget.message.conversationId,
    );

    // เมื่อกดยืนยันแล้ว (ทั้งฝั่งผู้เช่าและปล่อยเช่า) กด "รายละเอียดนัดรับ" จะเป็นการเปิดดูเส้นทางนัดรับบนแผนที่โดยตรง
    if (_isConfirmed) {
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

    if (isOwner) {
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
      if (mounted) {
        setState(() {
          _isConfirmed = true;
        });
      }
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. ภาพขนาดใหญ่จุใจ เห็นชัดเจนเต็มตา พร้อมแถบชื่อสินค้ามุมซ้ายล่าง
            GestureDetector(
              onTap: () {
                if (displayImageUrl.isNotEmpty) {
                  FullScreenImageViewer.open(
                    context,
                    imageUrls: [displayImageUrl],
                    initialIndex: 0,
                  );
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 225,
                      color: const Color(0xFFF1F5F9),
                      child: displayImageUrl.isNotEmpty
                          ? CachedNetworkImage(
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

                    // ป้ายชื่ออุปกรณ์โปร่งแสงที่มุมซ้ายล่าง (■ [ชื่อสินค้า])
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.5,
                          vertical: 4.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: const Color(0xFF9333EA),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 200),
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMine
                        ? 'คุณส่งรายละเอียด'
                        : '$senderTextส่งรายละเอียด',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2022),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'ตรวจสอบอย่างละเอียดข้อมูลถูกต้องไหม',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF777A7C),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 3. กล่องข้อมูลการเช่าแบบกระชับ (เวลา/วัน, จุดนัดพบ, ราคา)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
              ),
              child: Column(
                children: [
                  // แถวเวลา/วัน
                  _buildMiniInfoRow(
                    icon: Icons.access_time_filled_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    label: 'เวลาเช่า',
                    value: widget.bookingData.formattedPeriodSummary,
                  ),
                  const SizedBox(height: 6),

                  // แถวจุดนัดพบ
                  _buildMiniInfoRow(
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFFEF4444),
                    label: 'จุดนัดพบ',
                    value: widget.bookingData.location,
                    onTap: () {
                      final coordinates = LocationService.resolveCoordinates(
                        locationName: widget.bookingData.location,
                        latitude: widget.bookingData.latitude,
                        longitude: widget.bookingData.longitude,
                      );
                      LocationService.openInExternalMaps(
                        coordinates.latitude,
                        coordinates.longitude,
                      );
                    },
                  ),
                  const SizedBox(height: 6),

                  // แถวยอดรวม
                  _buildMiniInfoRow(
                    icon: Icons.payments_rounded,
                    iconColor: const Color(0xFF10B981),
                    label: 'ยอดรวม',
                    value: _formatPrice(widget.bookingData.totalPrice),
                    isPrice: true,
                  ),
                  const SizedBox(height: 6),

                  // แถววิธีชำระเงิน
                  _buildMiniInfoRow(
                    icon: widget.bookingData.paymentMethod == 'promptpay'
                        ? Icons.qr_code_2_rounded
                        : Icons.account_balance_wallet_outlined,
                    iconColor: const Color(0xFF3B82F6),
                    label: 'การชำระเงิน',
                    value: widget.bookingData.paymentMethod == 'promptpay'
                        ? 'พร้อมเพย์ (ชำระเมื่อรับของ)'
                        : 'เงินสด (ชำระเมื่อรับของ)',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 4. ปุ่ม Action (เมื่อกดยืนยันแล้ว แสดงปุ่ม "รายละเอียดนัดรับ" ทั้งฝั่งผู้เช่าและปล่อยเช่า)
            if (_isConfirmed)
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  key: const ValueKey('chat-booking-action-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor:
                        AppColors.primaryColor.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: () => _handleAction(context, isOwnerUser),
                  icon: const Icon(
                    Icons.event_available_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'รายละเอียดนัดรับ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else if (isOwnerUser)
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton(
                  key: const ValueKey('chat-booking-action-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    side: const BorderSide(
                      color: Color(0xFFD8B4FE),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => _handleAction(context, true),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppColors.primaryColor,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'แก้ไข',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  key: const ValueKey('chat-booking-action-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: const Color(0xFF1E2022),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: () => _handleAction(context, false),
                  child: const Text(
                    'ตรวจสอบ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2022),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isPrice = false,
    VoidCallback? onTap,
  }) {
    final row = Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 5),
        Text(
          '$label:',
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
              fontWeight: isPrice ? FontWeight.bold : FontWeight.w600,
              color: isPrice ? AppColors.primaryColor : const Color(0xFF1E2022),
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.open_in_new_rounded,
            size: 11,
            color: AppColors.primaryColor,
          ),
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: row,
        ),
      );
    }

    return row;
  }
}
