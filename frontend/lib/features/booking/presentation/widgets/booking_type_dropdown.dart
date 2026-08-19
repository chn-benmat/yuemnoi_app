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

  void _showSelectionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E2E5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'เลือกรูปแบบการเช่า',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2022),
                  ),
                ),
                const SizedBox(height: 12),
                _OptionTile(
                  title: 'ต่อชั่วโมง (Hourly)',
                  subtitle: 'เหมาะสำหรับการใช้งานสั้นๆ ไม่กี่ชั่วโมง',
                  icon: Icons.access_time_rounded,
                  isSelected: selectedType == BookingRentalType.hourly,
                  onTap: () {
                    Navigator.pop(ctx);
                    onChanged(BookingRentalType.hourly);
                  },
                ),
                const SizedBox(height: 8),
                _OptionTile(
                  title: 'ต่อวัน (Daily)',
                  subtitle: 'เช่ารายวันเต็มวันขึ้นไป',
                  icon: Icons.calendar_month_rounded,
                  isSelected: selectedType == BookingRentalType.daily,
                  onTap: () {
                    Navigator.pop(ctx);
                    onChanged(BookingRentalType.daily);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

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
        InkWell(
          onTap: () => _showSelectionSheet(context),
          borderRadius: BorderRadius.circular(26),
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
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryColor.withValues(alpha: 0.08)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryColor : const Color(0xFFE8E9EC),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryColor
                    : const Color(0xFFEBECEE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF595C5D),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
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
                      fontSize: 12,
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
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
