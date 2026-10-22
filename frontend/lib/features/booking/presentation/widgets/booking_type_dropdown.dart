import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingTypeDropdown extends StatelessWidget {
  const BookingTypeDropdown({
    super.key,
    required this.selectedType,
    required this.onChanged,
    this.showError = false,
  });
  final BookingRentalType? selectedType;
  final ValueChanged<BookingRentalType> onChanged;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'รูปแบบการเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: Color(0xFF716A80),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final type in BookingRentalType.values) ...[
              if (type != BookingRentalType.values.first)
                const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  selected: selectedType == type,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      foregroundColor: selectedType == type
                          ? AppColors.primaryColor
                          : const Color(0xFF716A80),
                      backgroundColor: selectedType == type
                          ? AppColors.primaryColor.withValues(alpha: 0.07)
                          : Colors.white,
                      side: BorderSide(
                        color: showError
                            ? const Color(0xFFDC2626)
                            : selectedType == type
                            ? AppColors.primaryColor
                            : const Color(0xFFE4DFEC),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => onChanged(type),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          type == BookingRentalType.daily
                              ? Icons.calendar_today_rounded
                              : Icons.schedule_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            type.label,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selectedType == type) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded, size: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (showError)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'กรุณาเลือกประเภทการเช่า',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
      ],
    );
  }
}
