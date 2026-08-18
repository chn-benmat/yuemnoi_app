import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

class ChatStackedImageCard extends StatelessWidget {
  const ChatStackedImageCard({
    super.key,
    required this.imageUrls,
    required this.isMine,
    this.onTap,
    this.onLongPress,
  });

  final List<String> imageUrls;
  final bool isMine;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final count = imageUrls.length;
    final primaryUrl = imageUrls.first;

    // ขนาดการ์ดรูปภาพ
    final cardWidth = MediaQuery.sizeOf(context).width * 0.58;
    const cardHeight = 220.0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        width: cardWidth + (count > 1 ? 16 : 0),
        height: cardHeight + (count > 1 ? 12 : 0),
        child: Stack(
          alignment: isMine ? Alignment.bottomRight : Alignment.bottomLeft,
          clipBehavior: Clip.none,
          children: [
            // Layer 3 (หลังสุด - สำหรับ 3 รูปขึ้นไป)
            if (count >= 3)
              Positioned(
                top: 0,
                left: isMine ? 0 : 12,
                right: isMine ? 12 : 0,
                bottom: 12,
                child: Transform.rotate(
                  angle: isMine ? -0.06 : 0.06,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Layer 2 (ชั้นกลาง - สำหรับ 2 รูปขึ้นไป)
            if (count >= 2)
              Positioned(
                top: 4,
                left: isMine ? 4 : 8,
                right: isMine ? 8 : 4,
                bottom: 8,
                child: Transform.rotate(
                  angle: isMine ? -0.03 : 0.03,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Layer 1 (ใบบนสุด - ภาพหลัก)
            Positioned(
              top: count > 1 ? 8 : 0,
              left: isMine ? (count > 1 ? 8 : 0) : 0,
              right: isMine ? 0 : (count > 1 ? 8 : 0),
              bottom: 0,
              child: Container(
                width: cardWidth,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: primaryUrl,
                        child: CachedNetworkImage(
                          imageUrl: primaryUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFFE2E8F0),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(Icons.broken_image_rounded, size: 40),
                          ),
                        ),
                      ),

                      // ป้ายแสดงจำนวนรูปภาพด้านล่างขวา เช่น "📷 3"
                      if (count > 1)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
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
          ],
        ),
      ),
    );
  }
}
