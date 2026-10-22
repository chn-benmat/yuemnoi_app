import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/chat_message.dart';
import 'chatbot_design.dart';

class AISummaryBottomSheet extends StatelessWidget {
  const AISummaryBottomSheet({super.key, required this.message});
  final ChatMessage message;

  static const _activityOrder = [
    'วิเคราะห์คำถาม',
    'เตรียมข้อมูล',
    'ตรวจคำตอบ',
    'สรุปคำตอบ',
  ];

  // หน้าสรุปใช้ชื่อขั้นตอนที่เสร็จแล้ว และรวมสถานะซ้ำจากการตรวจคำตอบหลายรอบ
  List<String> get _summaryActivities {
    final activities = message.activities
        .map(
          (activity) => switch (activity.trim()) {
            'กำลังวิเคราะห์คำถาม' => 'วิเคราะห์คำถาม',
            'กำลังเตรียมข้อมูล' || 'กำลังสร้างคำตอบ' => 'เตรียมข้อมูล',
            'กำลังตรวจคำตอบ' => 'ตรวจคำตอบ',
            'กำลังสรุปคำตอบ' || 'กำลังสรุปคำคำตอบ' => 'สรุปคำตอบ',
            final label => label,
          },
        )
        .where((activity) => activity.isNotEmpty)
        .toSet();
    return [
      for (final activity in _activityOrder)
        if (activities.contains(activity)) activity,
      for (final activity in activities)
        if (!_activityOrder.contains(activity)) activity,
    ];
  }

  static Future<void> show(BuildContext context, ChatMessage message) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: ChatbotDesign.maxWidth),
        builder: (context) => AISummaryBottomSheet(message: message),
      );

  Future<void> _openSourceUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      showAppPopup(
        context,
        content: Text('ไม่สามารถเปิดลิงก์ได้เนื่องจาก URL ไม่ถูกต้อง'),
      );
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        showAppPopup(context, content: Text('ไม่สามารถเปิดเบราว์เซอร์ได้'));
      }
    } catch (_) {
      if (context.mounted) {
        showAppPopup(context, content: Text('เกิดข้อผิดพลาดในการเปิดลิงก์'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activities = _summaryActivities;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      decoration: const BoxDecoration(
        color: ChatbotDesign.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: ChatbotDesign.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8, bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'สรุปคำแนะนำ',
                      style: ChatbotDesign.body.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: ChatbotDesign.muted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message.userQuery?.trim().isNotEmpty == true) ...[
                      _heading('ความต้องการที่คุณระบุ'),
                      Text(message.userQuery!, style: ChatbotDesign.body),
                      const SizedBox(height: 20),
                    ],
                    if (message.searchQuery?.trim().isNotEmpty == true) ...[
                      _heading('คำค้นที่ใช้'),
                      Text(message.searchQuery!, style: ChatbotDesign.body),
                      const SizedBox(height: 20),
                    ],
                    _heading('ขั้นตอนการทำงาน'),
                    if (activities.isEmpty)
                      Text(
                        'ไม่มีรายละเอียดการทำงานเพิ่มเติม',
                        style: ChatbotDesign.body.copyWith(
                          color: ChatbotDesign.muted,
                        ),
                      ),
                    for (final activity in activities)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: ChatbotDesign.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(activity, style: ChatbotDesign.body),
                            ),
                          ],
                        ),
                      ),
                    if (message.searchSources.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _heading(
                        'แหล่งข้อมูลอ้างอิง (${message.searchSources.length})',
                      ),
                    ],
                    for (final source in message.searchSources)
                      Material(
                        color: ChatbotDesign.surface,
                        child: InkWell(
                          onTap: () => _openSourceUrl(context, source.url),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.link_rounded,
                                  color: ChatbotDesign.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        source.title.isEmpty
                                            ? source.url
                                            : source.title,
                                        style: ChatbotDesign.body.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        source.domain,
                                        style: ChatbotDesign.body.copyWith(
                                          fontSize: 13,
                                          color: ChatbotDesign.muted,
                                        ),
                                      ),
                                      if (source.snippet?.trim().isNotEmpty ==
                                          true)
                                        Text(
                                          source.snippet!,
                                          style: ChatbotDesign.body.copyWith(
                                            fontSize: 14,
                                            color: ChatbotDesign.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                  color: ChatbotDesign.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
