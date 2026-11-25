import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';

class RentalTimeCard extends StatelessWidget {
  const RentalTimeCard({super.key, required this.session});

  final RentalReturnSession session;

  @override
  Widget build(BuildContext context) {
    final timingColor = session.isOverdue
        ? const Color(0xFFB91C1C)
        : session.isNearDeadline
        ? const Color(0xFF92400E)
        : AppColors.primaryColor;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          session.remainingDurationText,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: timingColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '#${session.orderNumber}',
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
