import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';
import 'skeleton_shimmer.dart';

class ProductListingCard extends StatelessWidget {
  const ProductListingCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.price,
    required this.locationName,
    required this.paidBookingCount,
    required this.isRentalOccupied,
    required this.onTap,
  });

  final String title;
  final String imageUrl;
  final int price;
  final String locationName;
  final int paidBookingCount;
  final bool isRentalOccupied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ส่วนภาพสินค้าอัตราส่วน 1:1 พร้อมป้าย Badge และปุ่มบันทึก
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        color: const Color(0xFFF3F4F6),
                        child: imageUrl.trim().isEmpty
                            ? _buildNoPictureThumbnail()
                            : imageUrl.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SkeletonShimmer(
                                      child: ColoredBox(
                                        color: Color(0xFFE3E5E8),
                                      ),
                                    ),
                                errorWidget: (context, url, error) =>
                                    _buildNoPictureThumbnail(),
                              )
                            : Image.asset(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildNoPictureThumbnail(),
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E2226),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (isRentalOccupied) ...[
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'กำลังถูกเช่า',
                          style: TextStyle(
                            color: Color(0xFF315FA6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '฿${_formatNumber(price)}',
                              style: const TextStyle(
                                color: AppColors.primaryColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (paidBookingCount > 0) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 3,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                'เช่าแล้ว ${_formatNumber(paidBookingCount)} ครั้ง',
                                style: const TextStyle(
                                  color: Color(0xFF7E848A),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Color(0xFF888E94),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            locationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF7E848A),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPictureThumbnail() {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFFADB5BD),
          size: 34,
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key, this.isRentalOccupied = false});

  /// การ์ดจริงที่กำลังถูกเช่ามีบรรทัด "กำลังถูกเช่า" เพิ่ม ทำให้การ์ดสูงขึ้น
  final bool isRentalOccupied;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        // เงาเดียวกับ ProductListingCard เพื่อให้ขอบการ์ดไม่เปลี่ยนตอนโหลดเสร็จ
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AspectRatio(
              aspectRatio: 1,
              child: SkeletonBox(height: double.infinity, borderRadius: 0),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ชื่อ 13px สูงบรรทัด 1.25
                  const _SkeletonLine(height: 16, bone: 12, widthFactor: 0.7),
                  if (isRentalOccupied) ...[
                    const SizedBox(height: 4),
                    const SizedBox(
                      height: 15,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SkeletonBox(
                          width: 56,
                          height: 11,
                          borderRadius: 4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // ราคา 17px ตัวหนา
                  const _SkeletonLine(height: 23, bone: 17, widthFactor: 0.4),
                  const SizedBox(height: 4),
                  // จุดนัดรับ: ไอคอน 12 กับข้อความ 11
                  const SizedBox(
                    height: 15,
                    child: Row(
                      children: [
                        SkeletonBox(
                          width: 12,
                          height: 12,
                          shape: BoxShape.circle,
                        ),
                        SizedBox(width: 2),
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.6,
                            child: SkeletonBox(height: 10, borderRadius: 4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.height,
    required this.bone,
    required this.widthFactor,
  });

  final double height;
  final double bone;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: SkeletonBox(height: bone, borderRadius: 5),
      ),
    ),
  );
}
