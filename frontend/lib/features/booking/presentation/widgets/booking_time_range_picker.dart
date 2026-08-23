import 'package:flutter/cupertino.dart';
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = startDate.isBefore(today) ? today : startDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'เลือกวันที่เริ่มเช่า',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
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
      final pickedDate = DateTime(picked.year, picked.month, picked.day);
      final currentEnd = DateTime(endDate.year, endDate.month, endDate.day);

      // ล็อคไม่ให้วันสิ้นสุดเป็นวันเดียวกับวันเริ่ม (ต้องเป็นวันถัดไปเป็นอย่างน้อย)
      final newEnd = currentEnd.isAfter(pickedDate)
          ? endDate
          : pickedDate.add(const Duration(days: 1));

      onDatesChanged!(pickedDate, newEnd);
    }
  }

  Future<void> _pickEndDate(BuildContext context) async {
    if (!isEditable || onDatesChanged == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ล็อคให้เลือกได้ตั้งแต่วันถัดไปของวันเริ่มต้นขึ้นไปเท่านั้น
    final minEndDate = startDate.add(const Duration(days: 1));
    final initial = endDate.isAfter(startDate) ? endDate : minEndDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minEndDate,
      lastDate: today.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'เลือกวันที่คืนอุปกรณ์',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
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
      final pickedDate = DateTime(picked.year, picked.month, picked.day);
      onDatesChanged!(startDate, pickedDate);
    }
  }

  Future<TimeOfDay?> _showWheelTimePicker({
    required BuildContext context,
    required TimeOfDay initialTime,
    required String title,
  }) async {
    TimeOfDay selected = initialTime;
    final now = DateTime.now();
    DateTime tempDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      initialTime.hour,
      initialTime.minute,
    );

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final formattedSelected =
                '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')} น.';

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // สัญลักษณ์ Drag Handle
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // หัวข้อและเวลาที่เลือก
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E2022),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              formattedSelected,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // วงล้อเลื่อนเวลา (Cupertino 24h Time Picker)
                      SizedBox(
                        height: 175,
                        child: CupertinoTheme(
                          data: const CupertinoThemeData(
                            textTheme: CupertinoTextThemeData(
                              pickerTextStyle: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E2022),
                              ),
                            ),
                          ),
                          child: CupertinoDatePicker(
                            key: const ValueKey('wheel-time-picker'),
                            mode: CupertinoDatePickerMode.time,
                            use24hFormat: true,
                            minuteInterval: 1,
                            initialDateTime: tempDateTime,
                            onDateTimeChanged: (DateTime newDateTime) {
                              setModalState(() {
                                tempDateTime = newDateTime;
                                selected = TimeOfDay(
                                  hour: newDateTime.hour,
                                  minute: newDateTime.minute,
                                );
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ปุ่ม "ตกลง"
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          key: const ValueKey('confirm-wheel-time-button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: const Text(
                            'ตกลง',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickStartTime(BuildContext context) async {
    if (!isEditable || onTimesChanged == null) return;

    final picked = await _showWheelTimePicker(
      context: context,
      initialTime: startTime,
      title: 'เลือกเวลาเริ่มเช่า',
    );

    if (picked != null) {
      final startMins = picked.hour * 60 + picked.minute;
      final endMins = endTime.hour * 60 + endTime.minute;

      TimeOfDay newEndTime = endTime;
      // หากเวลาสิ้นสุดน้อยกว่าหรือเท่ากับเวลาเริ่ม ปรับให้ห่าง 2 ชั่วโมงอัตโนมัติ
      if (endMins <= startMins) {
        final adjustedHour = (picked.hour + 2) <= 23 ? picked.hour + 2 : 23;
        newEndTime = TimeOfDay(hour: adjustedHour, minute: picked.minute);
      }

      onTimesChanged!(picked, newEndTime);
    }
  }

  Future<void> _pickEndTime(BuildContext context) async {
    if (!isEditable || onTimesChanged == null) return;

    final initialTime = (endTime.hour * 60 + endTime.minute <=
            startTime.hour * 60 + startTime.minute)
        ? TimeOfDay(
            hour: (startTime.hour + 2) <= 23 ? startTime.hour + 2 : 23,
            minute: startTime.minute,
          )
        : endTime;

    final picked = await _showWheelTimePicker(
      context: context,
      initialTime: initialTime,
      title: 'เลือกเวลาคืนอุปกรณ์',
    );

    if (picked != null) {
      final startMins = startTime.hour * 60 + startTime.minute;
      final pickedMins = picked.hour * 60 + picked.minute;

      if (pickedMins <= startMins) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เวลาคืนอุปกรณ์ต้องอยู่หลังเวลาเริ่มเช่า'),
              backgroundColor: Color(0xFFEF4444),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      onTimesChanged!(startTime, picked);
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute น.';
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
