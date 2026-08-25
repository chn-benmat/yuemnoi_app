import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingTypeDropdown extends StatelessWidget {
  const BookingTypeDropdown({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  final BookingRentalType selectedType;
  final ValueChanged<BookingRentalType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'กรุณาเลือก',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return PopupMenuButton<BookingRentalType>(
                initialValue: selectedType,
                position: PopupMenuPosition.under,
                offset: const Offset(0, 6),
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                ),
                padding: EdgeInsets.zero,
                onSelected: onChanged,
                itemBuilder: (ctx) => [
                  PopupMenuItem<BookingRentalType>(
                    value: BookingRentalType.hourly,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: _DropdownOptionTile(
                      title: 'ต่อชั่วโมง (Hourly)',
                      subtitle: 'เหมาะสำหรับการใช้งานสั้นๆ ไม่กี่ชั่วโมง',
                      icon: Icons.access_time_rounded,
                      isSelected: selectedType == BookingRentalType.hourly,
                    ),
                  ),
                  PopupMenuItem<BookingRentalType>(
                    value: BookingRentalType.daily,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: _DropdownOptionTile(
                      title: 'ต่อวัน (Daily)',
                      subtitle: 'เช่ารายวันเต็มวันขึ้นไป',
                      icon: Icons.calendar_month_rounded,
                      isSelected: selectedType == BookingRentalType.daily,
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedType.label,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E2022),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF1E2022),
                        size: 26,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DropdownOptionTile extends StatelessWidget {
  const _DropdownOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryColor.withValues(alpha: 0.08)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppColors.primaryColor : const Color(0xFFE8E9EC),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryColor
                  : const Color(0xFFEBECEE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF595C5D),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFF1E2022),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    color: Color(0xFF777A7C),
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primaryColor,
              size: 20,
            ),
        ],
      ),
    );
  }
}
