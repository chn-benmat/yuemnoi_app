import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

/// Modal Bottom Sheet แสดงสรุปขั้นตอนการทำงานของ AI และแหล่งข้อมูลอ้างอิง (AI Summary & Sources)
/// ได้รับแรงบันดาลใจจากอินเทอร์เฟซของ Perplexity / Gemini
class AISummaryBottomSheet extends StatelessWidget {
  const AISummaryBottomSheet({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  /// ฟังก์ชันเปิด Bottom Sheet สำหรับเรียกใช้จากทุกที่
  static Future<void> show(
    BuildContext context,
    ChatMessage message,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AISummaryBottomSheet(message: message),
    );
  }

  /// เปิดลิงก์เว็บไซต์อ้างอิงใน External Browser อย่างปลอดภัย
  Future<void> _openSourceUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ไม่สามารถเปิดลิงก์ได้เนื่องจาก URL ไม่ถูกต้อง',
              style: TextStyle(fontFamily: 'Prompt'),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ไม่สามารถเปิดเบราว์เซอร์ได้',
              style: TextStyle(fontFamily: 'Prompt'),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'เกิดข้อผิดพลาดในการเปิดลิงก์',
              style: TextStyle(fontFamily: 'Prompt'),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// จัดรูปแบบระยะเวลาที่ใช้ในการประมวลผล
  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final totalSeconds = duration.inSeconds;
    final displaySec = totalSeconds > 0 ? totalSeconds : 1;
    final minutes = displaySec ~/ 60;
    final seconds = displaySec % 60;
    if (minutes > 0) {
      return '$minutes นาที $seconds วินาที';
    }
    return '$seconds วินาที';
  }

  /// เลือกลำดับไอคอนสำหรับแต่ละขั้นตอนการทำงานของ AI
  IconData _getStepIcon(String stepText) {
    final lower = stepText.toLowerCase();
    if (lower.contains('google') ||
        lower.contains('อินเทอร์เน็ต') ||
        lower.contains('web')) {
      return Icons.public_rounded;
    } else if (lower.contains('คลัง') ||
        lower.contains('ระบบ') ||
        lower.contains('อุปกรณ์') ||
        lower.contains('db')) {
      return Icons.inventory_2_outlined;
    } else if (lower.contains('ตรวจสอบ') ||
        lower.contains('ยืนยัน') ||
        lower.contains('ถูกต้อง') ||
        lower.contains('สเปก')) {
      return Icons.verified_outlined;
    } else if (lower.contains('วิเคราะห์') ||
        lower.contains('เจตนา') ||
        lower.contains('คำถาม')) {
      return Icons.psychology_outlined;
    }
    return Icons.check_circle_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1F23) : Colors.white;
    final surfaceVariantColor =
        isDark ? const Color(0xFF282A2E) : const Color(0xFFF7F8FA);
    final borderColor =
        isDark ? const Color(0xFF383A40) : const Color(0xFFE8E9ED);
    final primaryTextColor =
        isDark ? const Color(0xFFF2F2F2) : const Color(0xFF1C1C1E);
    final secondaryTextColor =
        isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6E6E73);

    final durationText = _formatDuration(message.responseDuration);
    final activities = message.activities.isNotEmpty
        ? message.activities
        : [
            if (message.searchQuery != null)
              'ค้นหาข้อมูลจากอินเทอร์เน็ตผ่าน Google',
            'ค้นหาและตรวจสอบข้อมูลอุปกรณ์ในระบบ Yuemnoi',
            'สรุปและเรียบเรียงคำแนะนำ',
          ];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // แถบ Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF48484A)
                      : const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Title + ปุ่มปิด
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สรุปการทำงานของ AI',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        if (durationText.isNotEmpty)
                          Text(
                            'ประมวลผลเสร็จสิ้นใน $durationText',
                            style: TextStyle(
                              fontFamily: 'Prompt',
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: secondaryTextColor,
                    splashRadius: 20,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // เนื้อหาเลื่อนได้ (Scrollable Content)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ส่วนแสดง Google Search Query (ถ้ามี)
                    if (message.searchQuery != null &&
                        message.searchQuery!.trim().isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: surfaceVariantColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF33353A)
                                    : const Color(0xFFE9ECF2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: AppColors.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.public_rounded,
                                        size: 13,
                                        color: AppColors.primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Web Search Grounding (Tavily AI)',
                                        style: TextStyle(
                                          fontFamily: 'Prompt',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '“${message.searchQuery!.trim()}”',
                                    style: TextStyle(
                                      fontFamily: 'Prompt',
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: primaryTextColor,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ส่วนแสดง Timeline ขั้นตอนการทำงาน (Activity Timeline)
                    Row(
                      children: [
                        const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 16,
                          color: AppColors.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ขั้นตอนการทำงาน',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // รายการลำดับขั้นตอน (Vertical Stepper)
                    ...List.generate(activities.length, (index) {
                      final isLast = index == activities.length - 1;
                      final stepText = activities[index];
                      final icon = _getStepIcon(stepText);

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // คอลัมน์ไอคอนและเส้นเชื่อม
                            Column(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryColor
                                        .withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primaryColor
                                          .withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 15,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      color: isDark
                                          ? const Color(0xFF383A40)
                                          : const Color(0xFFE2E4E9),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),

                            // รายละเอียดขั้นตอน
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: 4,
                                  bottom: isLast ? 8 : 20,
                                ),
                                child: Text(
                                  stepText,
                                  style: TextStyle(
                                    fontFamily: 'Prompt',
                                    fontSize: 13.5,
                                    color: primaryTextColor,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // ส่วนแสดงแหล่งข้อมูลอ้างอิง (Reference Sources)
                    if (message.searchSources.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            size: 17,
                            color: AppColors.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'แหล่งข้อมูลอ้างอิง (${message.searchSources.length})',
                            style: TextStyle(
                              fontFamily: 'Prompt',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // การ์ดแสดงผลเว็บไซต์อ้างอิงแต่ละรายการ
                      ...message.searchSources.map((source) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openSourceUrl(context, source.url),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: surfaceVariantColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF383A40)
                                                : const Color(0xFFE5E7EB),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            Icons.language_rounded,
                                            size: 13,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            source.domain.isNotEmpty
                                                ? source.domain
                                                : 'เว็บไซต์อ้างอิง',
                                            style: TextStyle(
                                              fontFamily: 'Prompt',
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                              color: secondaryTextColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Icon(
                                          Icons.open_in_new_rounded,
                                          size: 14,
                                          color: secondaryTextColor,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      source.title.isNotEmpty
                                          ? source.title
                                          : source.url,
                                      style: TextStyle(
                                        fontFamily: 'Prompt',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: primaryTextColor,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (source.snippet != null &&
                                        source.snippet!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        source.snippet!.trim(),
                                        style: TextStyle(
                                          fontFamily: 'Prompt',
                                          fontSize: 12,
                                          color: secondaryTextColor,
                                          height: 1.35,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
