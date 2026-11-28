import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/models/pickup_location.dart';
import '../../../../core/widgets/longdo_map_view.dart';
import '../../../../core/theme/app_text_styles.dart';

class BookingLocationCard extends StatelessWidget {
  const BookingLocationCard({
    super.key,
    required this.location,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.showError = false,
  });

  final String location;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final point = mapPoint(latitude, longitude);
    final displaySubtitle = locationAddress?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'สถานที่นัดพบ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: showError
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF1F5F9),
              width: showError ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.place_rounded,
                  color: AppColors.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2022),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (displaySubtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        displaySubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (point != null && LongdoMapView.isAvailable) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 125,
              child: LongdoMapView(point: point, interactive: false),
            ),
          ),
        ],
        if (showError) ...[
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 16),
            child: Text(
              'กรุณาเลือกสถานที่นัดพบ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
