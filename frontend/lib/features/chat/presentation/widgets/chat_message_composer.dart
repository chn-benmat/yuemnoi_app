import 'chat_cached_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_reply_content.dart';

class ChatMessageComposer extends StatelessWidget {
  const ChatMessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
    this.replyingMessage,
    this.editingMessage,
    this.onCancelReplyOrEdit,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ChatMessage? replyingMessage;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelReplyOrEdit;

  @override
  Widget build(BuildContext context) {
    final isReplying = replyingMessage != null;
    final isEditing = editingMessage != null;
    final replyPreview = isReplying
        ? ChatReplyContent.preview(replyingMessage!)
        : null;

    return ColoredBox(
      color: const Color(0xFFF5F6F7),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReplying || isEditing)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit_rounded : Icons.reply_rounded,
                      size: 18,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    if (replyPreview?.imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: ChatCachedImage(
                              imageUrl: replyPreview!.imageUrl!,
                              fit: BoxFit.contain,
                              errorWidget: (_, _, _) =>
                                  const Icon(Icons.image, size: 20),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing
                                ? 'กำลังแก้ไขข้อความ'
                                : (replyingMessage!.isMine
                                      ? 'ตอบกลับตัวเอง'
                                      : 'กำลังตอบกลับ'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isEditing
                                ? ChatReplyContent.messageText(
                                    editingMessage!.message,
                                  )
                                : replyPreview!.text,
                            maxLines: isReplying ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isEditing ? 'ยกเลิกแก้ไข' : 'ยกเลิกตอบกลับ',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: const Color(0xFF9CA3AF),
                      onPressed: onCancelReplyOrEdit,
                    ),
                  ],
                ),
              ),
            _ChatComposerInputRow(
              controller: controller,
              onSend: onSend,
              onCamera: onCamera,
              onGallery: onGallery,
              isEditing: isEditing,
              isReplying: isReplying,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatComposerInputRow extends StatefulWidget {
  const _ChatComposerInputRow({
    required this.controller,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
    required this.isEditing,
    required this.isReplying,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final bool isEditing;
  final bool isReplying;

  @override
  State<_ChatComposerInputRow> createState() => _ChatComposerInputRowState();
}

class _ChatComposerInputRowState extends State<_ChatComposerInputRow> {
  final _focusNode = FocusNode(debugLabel: 'chat-message-composer');
  final _textScrollController = ScrollController();
  late String _lastText;
  late bool _attachmentsExpanded;

  @override
  void initState() {
    super.initState();
    _resetAttachments();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _ChatComposerInputRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      _resetAttachments();
      widget.controller.addListener(_onTextChanged);
    }
  }

  void _resetAttachments() {
    _lastText = widget.controller.text;
    _attachmentsExpanded = _lastText.isEmpty;
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    // การเลื่อนเคอร์เซอร์ไม่ควรหุบเครื่องมือที่ผู้ใช้เพิ่งขยาย
    if (_lastText == text) return;
    _lastText = text;
    if (_attachmentsExpanded != text.isEmpty) {
      setState(() => _attachmentsExpanded = text.isEmpty);
    }
  }

  void _expandAttachments() {
    setState(() => _attachmentsExpanded = true);
    _focusNode.requestFocus();
    _revealLatestText();
  }

  void _revealLatestText() {
    if (!_attachmentsExpanded) return;
    // รอให้ช่องพิมพ์ย่อและตัดบรรทัดใหม่ก่อนเลื่อน ไม่แก้ข้อความหรือเคอร์เซอร์
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_attachmentsExpanded ||
          !_textScrollController.hasClients) {
        return;
      }
      final position = _textScrollController.position;
      if (position.hasContentDimensions) {
        _textScrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _textScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final toggle = SizedBox(
      width: 32,
      height: 44,
      child: IconButton(
        key: const ValueKey('chat-attachments-toggle'),
        tooltip: 'แสดงกล้องและแกลเลอรี',
        padding: EdgeInsets.zero,
        onPressed: _expandAttachments,
        color: AppColors.primaryColor,
        icon: const Icon(Icons.chevron_right_rounded, size: 28),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomLeft,
          onEnd: _revealLatestText,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_attachmentsExpanded) toggle,
              if (_attachmentsExpanded) ...[
                SizedBox.square(
                  dimension: 42,
                  child: IconButton.filled(
                    key: const ValueKey('camera-button'),
                    tooltip: 'ถ่ายภาพ',
                    onPressed: widget.onCamera,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryColor,
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox.square(
                  dimension: 42,
                  child: IconButton.filled(
                    key: const ValueKey('gallery-button'),
                    tooltip: 'เลือกรูปภาพ',
                    onPressed: widget.onGallery,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4F5460),
                    ),
                    icon: const Icon(Icons.photo_library_rounded, size: 22),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ConstrainedBox(
            // จำกัดความสูงแทน maxLines: 1 เพื่อไม่ให้บรรทัดใหม่หายเมื่อพิมพ์ต่อ
            constraints: BoxConstraints(
              maxHeight: hasText && _attachmentsExpanded
                  ? MediaQuery.textScalerOf(context).scale(24) + 24
                  : double.infinity,
            ),
            child: TextField(
              key: const ValueKey('chat-message-field'),
              controller: widget.controller,
              scrollController: _textScrollController,
              focusNode: _focusNode,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.isEditing
                    ? 'แก้ไขข้อความ...'
                    : (widget.isReplying
                          ? 'ตอบกลับข้อความ...'
                          : 'พิมพ์ข้อความ...'),
                hintStyle: const TextStyle(
                  color: Color(0xFF7A8090),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox.square(
          dimension: 44,
          child: IconButton.filled(
            key: const ValueKey('send-message-button'),
            tooltip: widget.isEditing ? 'บันทึกแก้ไข' : 'ส่งข้อความ',
            onPressed: widget.onSend,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 3,
            ),
            icon: Icon(
              widget.isEditing ? Icons.check_rounded : Icons.send_rounded,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}
