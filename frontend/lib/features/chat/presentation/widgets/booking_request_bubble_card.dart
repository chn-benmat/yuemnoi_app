import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';
import '../../domain/entities/chat_message.dart';

class BookingRequestBubbleCard extends StatelessWidget {
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

  bool _checkIsOwner() {
    if (isOwner != null) return isOwner!;
    return message.isMine;
  }

  void _handleAction(BuildContext context, bool isOwner) {
    final attachedData = bookingData.copyWith(
      originalMessageId: message.id,
      conversationId: bookingData.conversationId ?? message.conversationId,
    );

    if (isOwner) {
      AppRoutes.openBooking(
        context,
        initialData: attachedData,
        isEditMode: true,
      );
    } else {
      AppRoutes.openBookingConfirmation(
        context,
        bookingData: attachedData,
      );
    }
  }

  String _formatPrice(double price) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(price)} ฿';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final item = bookingData.item;
    final displayImageUrl =
        (message.imageUrl != null && message.imageUrl!.isNotEmpty)
            ? message.imageUrl!
            : item.imageUrl;
    final isOwnerUser = _checkIsOwner();

    final senderText = (senderName != null && senderName!.isNotEmpty)
        ? senderName!
        : (item.ownerName.isNotEmpty ? item.ownerName : 'ผู้เช่า');

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
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
                    isMine ? 'คุณส่งรายละเอียด' : '$senderTextส่งรายละเอียด',
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
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: Column(
                children: [
                  // แถวเวลา/วัน
                  _buildMiniInfoRow(
                    icon: Icons.access_time_filled_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    label: 'เวลาเช่า',
                    value: bookingData.formattedPeriodSummary,
                  ),
                  const SizedBox(height: 6),

                  // แถวจุดนัดพบ
                  _buildMiniInfoRow(
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFFEF4444),
                    label: 'จุดนัดพบ',
                    value: bookingData.location,
                  ),
                  const SizedBox(height: 6),

                  // แถวยอดรวม
                  _buildMiniInfoRow(
                    icon: Icons.payments_rounded,
                    iconColor: const Color(0xFF10B981),
                    label: 'ยอดรวม',
                    value: _formatPrice(bookingData.totalPrice),
                    isPrice: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 4. ปุ่ม Action Minimal (แก้ไขรายละเอียดการเช่า / ตรวจสอบ)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                key: const ValueKey('chat-booking-action-button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE5E7EB),
                  foregroundColor: const Color(0xFF1E2022),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => _handleAction(context, isOwnerUser),
                child: Text(
                  isOwnerUser ? 'แก้ไขรายละเอียดการเช่า' : 'ตรวจสอบ',
                  style: const TextStyle(
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
  }) {
    return Row(
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
      ],
    );
  }
}
