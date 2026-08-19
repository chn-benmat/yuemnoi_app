import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingTimeRangePicker extends StatelessWidget {
  const BookingTimeRangePicker({
    super.key,
    required this.rentalType,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.onDatesChanged,
    this.onTimesChanged,
    this.isEditable = true,
    this.sectionTitle,
  });

  final BookingRentalType rentalType;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final void Function(DateTime start, DateTime end)? onDatesChanged;
  final void Function(TimeOfDay start, TimeOfDay end)? onTimesChanged;
  final bool isEditable;
  final String? sectionTitle;

  Future<void> _pickStartDate(BuildContext context) async {
    if (!isEditable || onDatesChanged == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryColor,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E2022),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final newEnd = picked.isAfter(endDate) ? picked : endDate;
      onDatesChanged!(picked, newEnd);
    }
  }

  Future<void> _pickEndDate(BuildContext context) async {
    if (!isEditable || onDatesChanged == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate.isBefore(startDate) ? startDate : endDate,
      firstDate: startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryColor,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E2022),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onDatesChanged!(startDate, picked);
    }
  }

  Future<void> _pickStartTime(BuildContext context) async {
    if (!isEditable || onTimesChanged == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: startTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryColor,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E2022),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onTimesChanged!(picked, endTime);
    }
  }

  Future<void> _pickEndTime(BuildContext context) async {
    if (!isEditable || onTimesChanged == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryColor,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E2022),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onTimesChanged!(startTime, picked);
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour : $minute';
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isHourly = rentalType == BookingRentalType.hourly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sectionTitle != null) ...[
          Text(
            sectionTitle!,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF595C5D),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            // ฝั่งเริ่ม
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เริ่ม',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PillButton(
                    icon: isHourly
                        ? Icons.access_time_filled_rounded
                        : Icons.calendar_month_rounded,
                    label: isHourly ? _formatTime(startTime) : _formatDate(startDate),
                    onTap: isEditable
                        ? () => isHourly
                            ? _pickStartTime(context)
                            : _pickStartDate(context)
                        : null,
                  ),
                ],
              ),
            ),
            // ลูกศรตรงกลาง
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 26, 10, 0),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFFC185FF),
                  size: 24,
                ),
              ),
            ),
            // ฝั่งสิ้นสุด
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'สิ้นสุด',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF595C5D),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PillButton(
                    icon: isHourly
                        ? Icons.access_time_filled_rounded
                        : Icons.calendar_month_rounded,
                    label: isHourly ? _formatTime(endTime) : _formatDate(endDate),
                    onTap: isEditable
                        ? () => isHourly
                            ? _pickEndTime(context)
                            : _pickEndDate(context)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: AppColors.primaryColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2022),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
