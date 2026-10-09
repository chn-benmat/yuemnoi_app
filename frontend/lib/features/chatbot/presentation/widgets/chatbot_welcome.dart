import 'package:flutter/material.dart';
import '../bloc/chatbot_state.dart';
import 'chatbot_design.dart';

class ChatbotWelcome extends StatelessWidget {
  const ChatbotWelcome({required this.onSelect, super.key});
  final ValueChanged<String> onSelect;

  static const _topics = [
    ('ถ่ายคอนเทนต์', Icons.camera_alt_outlined),
    ('ทำโปรเจกต์', Icons.laptop_mac_outlined),
    ('ไปทริป', Icons.terrain_outlined),
    ('เล่นเกม', Icons.sports_esports_outlined),
    ('เล่นดนตรี', Icons.music_note_outlined),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: const Key('chatbot-welcome'),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ChatbotDesign.subtle,
                  borderRadius: BorderRadius.circular(ChatbotDesign.radius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/images/yuemnoi.png',
                    width: 48,
                    height: 48,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('วันนี้อยากใช้อะไร?', style: ChatbotDesign.title),
              const SizedBox(height: 10),
              Text(
                'เล่างานที่อยากทำ หรืองบที่มี\nเดี๋ยวช่วยเลือกอุปกรณ์ให้',
                style: ChatbotDesign.body.copyWith(color: ChatbotDesign.muted),
              ),
              const SizedBox(height: 28),
              const Text(
                'ลองเริ่มจากสิ่งที่อยากทำ',
                style: ChatbotDesign.caption,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  for (var index = 0; index < _topics.length; index++)
                    Material(
                      color: ChatbotDesign.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: ChatbotDesign.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('chatbot-quick-reply-$index'),
                        onTap: () => onSelect(
                          ChatbotState.defaultInitialSuggestions[index],
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _topics[index].$2,
                                  color: ChatbotDesign.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _topics[index].$1,
                                    style: ChatbotDesign.body.copyWith(
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'แตะตัวอย่าง แล้วเพิ่มรายละเอียดก่อนส่งได้เลย',
                style: ChatbotDesign.caption,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
