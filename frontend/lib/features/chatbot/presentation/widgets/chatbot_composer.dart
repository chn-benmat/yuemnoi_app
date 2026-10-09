import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.customQuestionTitle,
    this.onCancelCustomAnswer,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelEdit;
  final String? customQuestionTitle;
  final VoidCallback? onCancelCustomAnswer;

  void _sendIfAvailable() {
    if (!isSending && controller.text.trim().isNotEmpty) onSend();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    // ให้ Enter ยืนยันคำที่กำลังสะกดก่อนส่งข้อความ
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    // ส่งครั้งเดียวเมื่อกดปุ่ม และไม่แทรกบรรทัดใหม่เมื่อกดค้าง
    if (event is KeyDownEvent) _sendIfAvailable();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ChatbotDesign.surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ChatbotDesign.maxWidth),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = value.text.trim().isNotEmpty;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (editingMessage != null || customQuestionTitle != null)
                    Container(
                      key: Key(
                        editingMessage != null
                            ? 'chatbot-editing-banner'
                            : 'chatbot-custom-answer-banner',
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
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
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              editingMessage != null
                                  ? 'กำลังแก้ไขข้อความ'
                                  : 'ตอบ: $customQuestionTitle',
                              style: ChatbotDesign.caption.copyWith(
                                color: ChatbotDesign.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            key: Key(
                              editingMessage != null
                                  ? 'chatbot-cancel-edit-button'
                                  : 'chatbot-cancel-custom-answer-button',
                            ),
                            onPressed: editingMessage != null
                                ? onCancelEdit
                                : onCancelCustomAnswer,
                            style: TextButton.styleFrom(
                              minimumSize: ChatbotDesign.button,
                            ),
                            child: const Text('ยกเลิก'),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    key: const Key('chatbot-composer'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: ChatbotDesign.subtle,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: ChatbotDesign.border),
                      boxShadow: ChatbotDesign.shadow,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: _handleKeyEvent,
                            child: TextField(
                              key: const Key('chatbot-message-field'),
                              controller: controller,
                              focusNode: focusNode,
                              enabled: !isSending,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              style: ChatbotDesign.body,
                              onSubmitted: (_) => _sendIfAvailable(),
                              buildCounter:
                                  (
                                    context, {
                                    required currentLength,
                                    required isFocused,
                                    required maxLength,
                                  }) => currentLength < 160
                                  ? null
                                  : Text(
                                      '$currentLength',
                                      key: const Key(
                                        'chatbot-character-counter',
                                      ),
                                      semanticsLabel: '$currentLength ตัวอักษร',
                                      style: ChatbotDesign.caption,
                                    ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                hintText: editingMessage != null
                                    ? 'แก้ไขข้อความ...'
                                    : customQuestionTitle != null
                                    ? 'พิมพ์คำตอบของข้อนี้...'
                                    : 'เล่างานที่อยากทำ...',
                                hintStyle: ChatbotDesign.body.copyWith(
                                  color: ChatbotDesign.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          key: const Key('chatbot-send-gradient'),
                          decoration: BoxDecoration(
                            color: isSending || canSend
                                ? ChatbotDesign.primary
                                : ChatbotDesign.border,
                            borderRadius: BorderRadius.circular(16),
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
                            onPressed: isSending
                                ? onStop
                                : canSend
                                ? onSend
                                : null,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: ChatbotDesign.muted,
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
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
