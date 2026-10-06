import 'package:flutter/material.dart';
import '../../domain/entities/chat_message.dart';
import 'chatbot_design.dart';

class ChatbotComposer extends StatelessWidget {
  const ChatbotComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    this.onStop,
    this.editingMessage,
    this.onCancelEdit,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ChatbotDesign.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ChatbotDesign.maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editingMessage != null)
                Container(
                  key: const Key('chatbot-editing-banner'),
                  padding: const EdgeInsets.only(left: 12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: ChatbotDesign.tint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        color: ChatbotDesign.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'กำลังแก้ไขข้อความ',
                          style: TextStyle(
                            fontFamily: 'Prompt',
                            fontSize: 14,
                            color: ChatbotDesign.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('chatbot-cancel-edit-button'),
                        tooltip: 'ยกเลิกแก้ไข',
                        onPressed: onCancelEdit,
                        icon: const Icon(Icons.close_rounded),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      key: const Key('chatbot-composer'),
                      padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: ChatbotDesign.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: ChatbotDesign.border),
                      ),
                      child: TextField(
                        key: const Key('chatbot-message-field'),
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !isSending,
                        maxLength: 200,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        style: ChatbotDesign.body,
                        onSubmitted: (_) => onSend(),
                        buildCounter:
                            (
                              context, {
                              required currentLength,
                              required isFocused,
                              required maxLength,
                            }) => Text(
                              '$currentLength/$maxLength',
                              key: const Key('chatbot-character-counter'),
                              semanticsLabel:
                                  '$currentLength จาก $maxLength ตัวอักษร',
                              style: const TextStyle(
                                fontFamily: 'Prompt',
                                fontSize: 12,
                                color: ChatbotDesign.muted,
                              ),
                            ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: editingMessage != null
                              ? 'แก้ไขข้อความ...'
                              : 'บอกงานที่ต้องใช้และงบประมาณ',
                          hintStyle: ChatbotDesign.body.copyWith(
                            color: ChatbotDesign.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          key: const Key('chatbot-send-gradient'),
                          decoration: const BoxDecoration(
                            color: ChatbotDesign.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            key: Key(
                              isSending
                                  ? 'chatbot-stop-button'
                                  : 'chatbot-send-button',
                            ),
                            tooltip: isSending
                                ? 'หยุดตอบ'
                                : editingMessage != null
                                ? 'บันทึกแก้ไข'
                                : 'ส่งข้อความ',
                            onPressed: isSending ? onStop : onSend,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white54,
                              minimumSize: ChatbotDesign.button,
                            ),
                            icon: isSending
                                ? const Icon(
                                    Icons.stop_rounded,
                                    key: Key('chatbot-stop-icon'),
                                  )
                                : Icon(
                                    editingMessage != null
                                        ? Icons.check_rounded
                                        : Icons.arrow_upward_rounded,
                                  ),
                          ),
                        ),
                        if (isSending)
                          const Text(
                            'หยุดตอบ',
                            style: TextStyle(
                              fontFamily: 'Prompt',
                              fontSize: 12,
                              color: ChatbotDesign.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
