import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/item_inquiry_data.dart';

class ItemInquiryBubbleCard extends StatelessWidget {
  const ItemInquiryBubbleCard({
    super.key,
    required this.message,
    required this.inquiryData,
    this.isOwner,
    this.onSendBookingRequest,
    this.onTap,
  });

  final ChatMessage message;
  final ItemInquiryData inquiryData;
  final bool? isOwner;
  final void Function(ItemInquiryData)? onSendBookingRequest;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final displayImageUrl =
        (message.imageUrl != null && message.imageUrl!.isNotEmpty)
        ? message.imageUrl!
        : (inquiryData.imageUrl ?? '');
    final itemId = inquiryData.itemId;

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
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
            // 1. หัวข้อข้อความแสดงความสนใจ
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2022),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 2. ภาพสินค้าขนาดใหญ่ คมชัด สวยงาม (กดเพื่อดูภาพขนาดเต็มได้)
            if (displayImageUrl.isNotEmpty)
              GestureDetector(
                onTap: () {
                  FullScreenImageViewer.open(
                    context,
                    imageUrls: [displayImageUrl],
                    initialIndex: 0,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    height: 160,
                    color: const Color(0xFFF1F5F9),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: displayImageUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          placeholder: (_, _) => const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Color(0xFF94A3B8),
                              size: 32,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fullscreen_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'แตะเพื่อดูรูป',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
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
              ),

            if (displayImageUrl.isNotEmpty) const SizedBox(height: 10),

            // 3. กล่องรายละเอียดชื่ออุปกรณ์และราคา
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // แถวชื่ออุปกรณ์
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'อุปกรณ์: ',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          inquiryData.itemName,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // แถวราคา
                  if (inquiryData.displayPrice.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'ราคา: ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            inquiryData.displayPrice,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // 4. ปุ่มเปิดดูรายละเอียดอุปกรณ์ (หากมี itemId)
            if (itemId != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    side: const BorderSide(color: Color(0xFFD8B4FE), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () {
                    AppRoutes.openItemDetail(context, itemId: itemId);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'ดูรายละเอียดอุปกรณ์',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],

            // 5. ปุ่มแอ็กชันบนการ์ดสินค้า
            // - ถ้าเป็นผู้ปล่อยเช่า (isOwner == true): แสดง "สร้างข้อเสนอการเช่า / นัดรับ"
            // - ถ้าเป็นผู้เช่า (isOwner != true): แสดง "ส่งคำขอเช่าอุปกรณ์นี้"
            if (onSendBookingRequest != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  key: ValueKey(
                    'inquiry-send-request-${inquiryData.itemId ?? inquiryData.itemName}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => onSendBookingRequest!(inquiryData),
                  icon: Icon(
                    isOwner == true
                        ? Icons.receipt_long_rounded
                        : Icons.calendar_month_outlined,
                    size: 15,
                  ),
                  label: Text(
                    isOwner == true
                        ? 'สร้างข้อเสนอการเช่า / นัดรับ'
                        : 'ส่งคำขอเช่าอุปกรณ์นี้',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
