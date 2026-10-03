import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/colors.dart';
import '../theme/app_text_styles.dart';

/// วิดเจ็ตนับถอยหลังการส่งคืนอุปกรณ์ (Return Time Tracking & Countdown System)
/// ออกแบบตามแนวคิด Swiss Style & Clean SaaS:
/// 1. Visual Hierarchy ชัดเจน ไม่ใช้กล่องตัวเลขเทอะทะซ้อนกันหลายชั้น
/// 2. ใช้ 2 สีหลัก (ม่วง Yuemnoi สำหรับสถานะ Active และ แดงแจ้งเตือนสำหรับ Overdue)
/// 3. ไร้ข้อมูลซ้ำซ้อน แสดงทั้งกำหนดส่งคืนและเวลานับถอยหลัง/เลทอย่างกลมกลืน
class RentalCountdownTimerWidget extends StatefulWidget {
  final DateTime endDateTime;
  final DateTime? startDateTime;
  final String? rentalPeriodText;
  final bool isCompact;
  final VoidCallback? onReturnTap;
  final VoidCallback? onChatTap;
  final double? hourlyLateFee;
  final bool initialSimulateOverdue;
  final bool showDemoSwitcher;

  const RentalCountdownTimerWidget({
    super.key,
    required this.endDateTime,
    this.startDateTime,
    this.rentalPeriodText,
    this.isCompact = false,
    this.onReturnTap,
    this.onChatTap,
    this.hourlyLateFee,
    this.initialSimulateOverdue = false,
    this.showDemoSwitcher = false,
  });

  @override
  State<RentalCountdownTimerWidget> createState() =>
      _RentalCountdownTimerWidgetState();
}

class _RentalCountdownTimerWidgetState
    extends State<RentalCountdownTimerWidget> {
  Timer? _ticker;
  late DateTime _currentTime;
  late bool _simulateOverdue;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _simulateOverdue = widget.initialSimulateOverdue;
    _startTicker();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isActuallyOverdue = _currentTime.isAfter(widget.endDateTime);
    final bool isOverdue = _simulateOverdue || isActuallyOverdue;

    final Duration durationDiff;
    if (_simulateOverdue) {
      final baseSeconds = (2 * 3600) + (15 * 60) + 42;
      final addedSeconds = _currentTime.second % 60;
      durationDiff = Duration(seconds: baseSeconds + addedSeconds);
    } else if (isActuallyOverdue) {
      durationDiff = _currentTime.difference(widget.endDateTime);
    } else {
      durationDiff = widget.endDateTime.difference(_currentTime);
    }

    if (widget.isCompact) {
      return _buildCompactView(isOverdue, durationDiff);
    }

    return _buildFullCardView(isOverdue, durationDiff);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Compact View (สำหรับแท็กสั้นๆ ในรายการ)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCompactView(bool isOverdue, Duration diff) {
    final bgColor = isOverdue ? const Color(0xFFFEF2F2) : const Color(0xFFF5F3FF);
    final borderColor =
        isOverdue ? const Color(0xFFFECACA) : const Color(0xFFDDD6FE);
    final textColor = isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor;

    final String timeStr;
    final String statusLabel;

    if (isOverdue) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      final seconds = diff.inSeconds % 60;
      timeStr = '+${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      statusLabel = 'ส่งคืนเลท';
    } else {
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      final minutes = diff.inMinutes % 60;
      final seconds = diff.inSeconds % 60;

      if (days > 0) {
        timeStr = '$days วัน ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      } else {
        timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      }
      statusLabel = 'เหลือเวลาคืน';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.warning_rounded : Icons.timer_outlined,
            size: 14,
            color: textColor,
          ),
          const SizedBox(width: 5),
          Text(
            '$statusLabel: ',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          Text(
            timeStr,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Full Card View (Swiss Style & Clean SaaS - ไร้การ์ดซ้ำซ้อนและไร้กล่องตัวเลขเทอะทะ)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFullCardView(bool isOverdue, Duration diff) {
    final cardBg =
        isOverdue ? const Color(0xFFFFF8F8) : const Color(0xFFF8FAFC);
    final borderColor =
        isOverdue ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0);
    final accentColor =
        isOverdue ? const Color(0xFFDC2626) : AppColors.primaryColor;
    final headerBg =
        isOverdue ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9);

    final totalHours = diff.inHours;
    final days = diff.inDays;
    final hours = isOverdue ? totalHours : (totalHours % 24);
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    String endFormatted;
    try {
      endFormatted = DateFormat('d MMM yyyy • HH:mm น.', 'th')
          .format(widget.endDateTime);
    } catch (_) {
      endFormatted =
          '${widget.endDateTime.day}/${widget.endDateTime.month}/${widget.endDateTime.year} • ${widget.endDateTime.hour.toString().padLeft(2, '0')}:${widget.endDateTime.minute.toString().padLeft(2, '0')} น.';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Swiss Header Bar (Micro Indicator Dot + Minimal Monospace Tag) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          isOverdue
                              ? 'เลยกำหนดส่งคืน (Overdue)'
                              : 'ช่วงเวลาเช่า (Active)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isOverdue
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFCBD5E1),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isOverdue ? 'เลทสะสม' : 'นับถอยหลัง',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isOverdue
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 2. ตารางข้อมูลแบบ Swiss Grid (สะอาดตา ข้อมูลไม่ซ้ำซ้อน) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.rentalPeriodText != null &&
                    widget.rentalPeriodText!.isNotEmpty) ...[
                  _buildSwissDataRow(
                    label: 'เวลาเช่า',
                    value: widget.rentalPeriodText!,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(
                      height: 1,
                      thickness: 0.8,
                      color: isOverdue
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                ],

                // กำหนดส่งคืน / ครบกำหนดเมื่อ
                _buildSwissDataRow(
                  label: isOverdue ? 'ครบกำหนดเมื่อ' : 'กำหนดส่งคืน',
                  value: endFormatted,
                  valueColor: isOverdue
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF0F172A),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(
                    height: 1,
                    thickness: 0.8,
                    color: isOverdue
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFF1F5F9),
                  ),
                ),

                // ตัวจับเวลาเรียลไทม์ (Live Swiss Ticker)
                _buildSwissDataRow(
                  label: isOverdue ? 'ส่งคืนล่าช้า' : 'เวลาคงเหลือ',
                  isHighlighted: isOverdue,
                  valueWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (isOverdue) ...[
                        Text(
                          '+',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                      if (!isOverdue && days > 0) ...[
                        Text(
                          '$days',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          'วัน ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      Text(
                        hours.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'ชม.',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ':',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        minutes.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'นาที',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ':',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        seconds.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'วินาที',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── สวิตช์สลับโหมดจำลอง (เฉพาะกรณีเปิด Dev switcher) ──
          if (widget.showDemoSwitcher) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  const Text(
                    'ตัวอย่างต้นแบบ: ',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  _buildDemoChip(
                    label: 'กำลังเช่า',
                    isSelected: !_simulateOverdue,
                    onTap: () {
                      setState(() => _simulateOverdue = false);
                    },
                  ),
                  _buildDemoChip(
                    label: 'ส่งคืนเลท',
                    isSelected: _simulateOverdue,
                    isWarning: true,
                    onTap: () {
                      setState(() => _simulateOverdue = true);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwissDataRow({
    required String label,
    String? value,
    Widget? valueWidget,
    bool isHighlighted = false,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isHighlighted
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value ?? '',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11.5,
                      fontWeight:
                          isHighlighted ? FontWeight.w700 : FontWeight.w600,
                      color: valueColor ??
                          (isHighlighted
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0F172A)),
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDemoChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool isWarning = false,
  }) {
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF64748B);

    if (isSelected) {
      if (isWarning) {
        bg = const Color(0xFFDC2626);
        fg = Colors.white;
      } else {
        bg = AppColors.primaryColor;
        fg = Colors.white;
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}
