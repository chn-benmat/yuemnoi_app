import 'package:flutter/material.dart';
import '../bloc/chatbot_state.dart';
import 'chatbot_design.dart';

class ChatbotWelcome extends StatelessWidget {
  const ChatbotWelcome({required this.onSelect, super.key});
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: const Key('chatbot-welcome'),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/yuemnoi.png',
                  width: 80,
                  height: 80,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'หาอุปกรณ์ที่ใช่ ให้ AI ช่วย',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Prompt',
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                  color: ChatbotDesign.ink,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'เล่างานที่ต้องใช้ งบประมาณ หรือรุ่นที่สนใจ\nแล้วเราช่วยหาตัวเลือกให้',
                textAlign: TextAlign.center,
                style: ChatbotDesign.body,
              ),
              const SizedBox(height: 24),
              for (var index = 0; index < 3; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                Material(
                  color: ChatbotDesign.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: ChatbotDesign.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('chatbot-quick-reply-$index'),
                    onTap: () =>
                        onSelect(ChatbotState.defaultInitialSuggestions[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            [
                              Icons.camera_alt_outlined,
                              Icons.terrain_outlined,
                              Icons.laptop_mac_outlined,
                            ][index],
                            color: ChatbotDesign.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              [
                                'กล้องสำหรับถ่ายงาน',
                                'อุปกรณ์ไปแคมป์ปิ้ง',
                                'คอมพิวเตอร์ทำโปรเจกต์',
                              ][index],
                              style: ChatbotDesign.body,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: ChatbotDesign.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'แตะตัวอย่างเพื่อแก้ไขก่อนส่ง',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Prompt',
                  fontSize: 13,
                  color: ChatbotDesign.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
