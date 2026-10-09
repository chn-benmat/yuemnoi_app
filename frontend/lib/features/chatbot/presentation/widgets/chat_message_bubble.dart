import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../domain/entities/chat_message.dart';
import 'interactive_questionnaire_card.dart';
import 'ai_summary_bottom_sheet.dart';
import 'chatbot_design.dart';
import 'chatbot_state_card.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.onRentPressed,
    this.animateAssistantResponse = false,
    this.onAnimationStarted,
    this.onTextProgress,
    this.onCardRevealed,
    this.onContentRendered,
    this.onEdit,
    this.onOptionSelected,
    this.onReviseQuery,
    this.questionnaire,
    super.key,
  });
  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animateAssistantResponse;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onTextProgress;
  final VoidCallback? onCardRevealed;
  final VoidCallback? onContentRendered;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onOptionSelected;
  final VoidCallback? onReviseQuery;
  final Widget? questionnaire;

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatMessageRole.user) {
      return LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onLongPress: onEdit,
                  child: Container(
                    key: ValueKey('chat-user-${message.content}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: ChatbotDesign.tint,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(6),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Text(message.content, style: ChatbotDesign.body),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    key: ValueKey('chatbot-message-actions-${message.content}'),
                    tooltip: 'คัดลอกหรือแก้ไขข้อความ',
                    onPressed: onEdit,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: ChatbotDesign.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = _AssistantContent(
          key: ValueKey('assistant-content-${message.id}'),
          message: message,
          onRentPressed: onRentPressed,
          animate: animateAssistantResponse,
          onAnimationStarted: onAnimationStarted,
          onProgress: onTextProgress,
          onCardRevealed: onCardRevealed,
          onContentRendered: onContentRendered,
          onReviseQuery: onReviseQuery,
          questionnaire: questionnaire,
        );
        return constraints.hasBoundedHeight
            ? SingleChildScrollView(child: content)
            : content;
      },
    );
  }
}

class _AssistantContent extends StatefulWidget {
  const _AssistantContent({
    required this.message,
    required this.onRentPressed,
    required this.animate,
    this.onAnimationStarted,
    this.onProgress,
    this.onCardRevealed,
    this.onContentRendered,
    this.onReviseQuery,
    this.questionnaire,
    super.key,
  });
  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;
  final VoidCallback? onCardRevealed;
  final VoidCallback? onContentRendered;
  final VoidCallback? onReviseQuery;
  final Widget? questionnaire;
  @override
  State<_AssistantContent> createState() => _AssistantContentState();
}

class _AssistantContentState extends State<_AssistantContent> {
  late final bool _animateEntrance;
  bool _observationScheduled = false;
  bool _notifyProgress = false;
  bool _notifyCards = false;

  @override
  void initState() {
    super.initState();
    _animateEntrance = widget.animate;
    if (_animateEntrance) widget.onAnimationStarted?.call();
    _observeAfterFrame(progress: false, cards: _hasVisibleCards);
  }

  bool get _hasVisibleCards =>
      !widget.message.isStreaming &&
      !widget.message.questions.any((q) => q.selectedOption == null) &&
      widget.message.recommendedItems.isNotEmpty;

  @override
  void didUpdateWidget(covariant _AssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _observeAfterFrame(
        progress: oldWidget.message.content != widget.message.content,
        cards:
            _hasVisibleCards &&
            (oldWidget.message.isStreaming ||
                oldWidget.message.recommendedItems !=
                    widget.message.recommendedItems),
      );
    }
  }

  // แจ้งผลหลังวาดเฟรมและรวม callback เพื่อไม่สั่งเลื่อนจาก build หรือทุกตัวอักษร
  void _observeAfterFrame({required bool progress, required bool cards}) {
    _notifyProgress |= progress;
    _notifyCards |= cards;
    if (_observationScheduled) return;
    _observationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _observationScheduled = false;
      if (!mounted) return;
      final notifyProgress = _notifyProgress;
      final notifyCards = _notifyCards;
      _notifyProgress = _notifyCards = false;
      if (notifyProgress) widget.onProgress?.call();
      if (notifyCards) widget.onCardRevealed?.call();
      if (!widget.message.isStreaming) widget.onContentRendered?.call();
    });
  }

  static final _markdownStyleSheet = MarkdownStyleSheet(
    p: ChatbotDesign.body,
    pPadding: const EdgeInsets.only(bottom: 8),
    h1: ChatbotDesign.body.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
    h2: ChatbotDesign.body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
    h3: ChatbotDesign.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h3Padding: const EdgeInsets.only(top: 12, bottom: 6),
    strong: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w600),
    listBullet: ChatbotDesign.body,
    listIndent: 18,
    blockSpacing: 8,
    blockquote: ChatbotDesign.body.copyWith(color: ChatbotDesign.muted),
    blockquotePadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      color: ChatbotDesign.subtle,
      borderRadius: BorderRadius.circular(12),
      border: const Border(
        left: BorderSide(color: ChatbotDesign.border, width: 3),
      ),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ChatbotDesign.border)),
    ),
    tableBorder: TableBorder.all(color: ChatbotDesign.border),
    tableHead: ChatbotDesign.caption.copyWith(fontWeight: FontWeight.w600),
    tableBody: ChatbotDesign.caption.copyWith(color: ChatbotDesign.ink),
    tablePadding: const EdgeInsets.all(8),
  );

  String get _content {
    final message = widget.message;
    if (message.content.trim().isNotEmpty) return message.content;
    if (message.isStreaming ||
        message.recommendedItems.isNotEmpty ||
        message.questions.isNotEmpty) {
      return '';
    }
    return 'การตอบกลับไม่สมบูรณ์ ลองส่งคำถามอีกครั้งนะ';
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final content = _content;
    final isComplete = !message.isStreaming;
    final items = message.recommendedItems;
    return Column(
      key: const ValueKey('chat-assistant-bubble'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isComplete)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('chatbot-status-header-button-${message.id}'),
              onPressed: () => AISummaryBottomSheet.show(context, message),
              style: TextButton.styleFrom(
                foregroundColor: ChatbotDesign.muted,
                minimumSize: ChatbotDesign.button,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'สรุปคำแนะนำ'),
                    if (message.responseDuration != null)
                      TextSpan(
                        text: ' ${message.responseDuration!.inSeconds} วินาที',
                      ),
                    const TextSpan(
                      text: ' >',
                      style: TextStyle(color: ChatbotDesign.primary),
                    ),
                  ],
                ),
                style: ChatbotDesign.caption,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                key: ValueKey('chatbot-assistant-avatar-${message.id}'),
                child: Image.asset(
                  'assets/images/yuemnoi.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: content.isEmpty
                    ? const SizedBox.shrink()
                    : _containsMarkdown(content)
                    ? MarkdownBody(
                        key: ValueKey(
                          'chatbot-markdown-response-${message.id}',
                        ),
                        data: content,
                        styleSheet: _markdownStyleSheet,
                      )
                    : Text(
                        content,
                        key: ValueKey(
                          'chatbot-animated-response-${message.id}',
                        ),
                        style: ChatbotDesign.body,
                      ),
              ),
            ],
          ),
        ),
        if (message.questions.any((q) => q.selectedOption != null))
          QuestionnaireRecapCard(questions: message.questions),
        if (widget.questionnaire != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: widget.questionnaire,
          ),
        if (isComplete &&
            items.isEmpty &&
            message.questions.isEmpty &&
            [
              'recommendation',
              'overview',
            ].contains(message.understanding?.responseKind)) ...[
          const SizedBox(height: 12),
          ChatbotStateCard(
            key: const Key('chatbot-empty-results'),
            title: 'ยังไม่เจออุปกรณ์ที่ตรง',
            description: 'ลองปรับงบ หรือบอกประเภทอุปกรณ์เพิ่มได้เลย',
            icon: Icons.search_rounded,
            actionLabel: 'ปรับคำถาม',
            onAction: widget.onReviseQuery,
          ),
        ],
        if (_hasVisibleCards)
          for (var index = 0; index < items.length; index++) ...[
            const SizedBox(height: 10),
            _CardEntrance(
              key: ValueKey('staggered-card-${message.id}-$index'),
              animate: _animateEntrance,
              child: RecommendedItemCard(
                item: items[index],
                messageContent: content,
                onPressed: () => widget.onRentPressed(items[index]),
              ),
            ),
          ],
        if (!isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message.statusMessage?.trim().isNotEmpty == true
                  ? message.statusMessage!
                  : 'กำลังเรียบเรียงคำตอบ',
              key: ValueKey('chatbot-status-header-${message.id}'),
              style: ChatbotDesign.caption,
            ),
          ),
      ],
    );
  }

  // ตรวจเฉพาะรูปแบบ Markdown โดยไม่เปลี่ยนเนื้อหาหรือข้อมูลจากบริการ
  static bool _containsMarkdown(String text) => [
    '#',
    '**',
    '* ',
    '- ',
    '>',
    String.fromCharCode(96),
    '|',
    '[',
    '. ',
  ].any(text.contains);
}

class _CardEntrance extends StatelessWidget {
  const _CardEntrance({required this.child, required this.animate, super.key});
  final Widget child;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: ChatbotDesign.motion,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: .9 + .1 * value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class RecommendedItemCard extends StatelessWidget {
  const RecommendedItemCard({
    required this.item,
    required this.onPressed,
    this.messageContent,
    super.key,
  });
  final RecommendedItem item;
  final VoidCallback onPressed;
  final String? messageContent;

  @override
  Widget build(BuildContext context) {
    final validId = item.id != null && item.id! > 0;
    final priceDisplay = item.priceDisplay?.trim();
    final hasPriceDisplay = priceDisplay?.isNotEmpty == true;
    final price = hasPriceDisplay
        ? priceDisplay!
        : item.price == null
        ? 'ไม่ระบุราคา'
        : '${_priceLabel(item.price!)} ฿';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: price,
                style: ChatbotDesign.body.copyWith(
                  color: item.price == null && !hasPriceDisplay
                      ? ChatbotDesign.muted
                      : ChatbotDesign.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!hasPriceDisplay && item.price != null)
                TextSpan(
                  text: ' / ${_formatUnit(item.unitDisplay ?? item.unit)}',
                  style: ChatbotDesign.caption,
                ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: validId,
      enabled: validId,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ChatbotDesign.radius),
          boxShadow: ChatbotDesign.shadow,
        ),
        child: Material(
          color: ChatbotDesign.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChatbotDesign.radius),
            side: const BorderSide(color: ChatbotDesign.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('recommended-item-${item.id ?? item.name}'),
            onTap: validId ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      MediaQuery.sizeOf(context).width < 320 ||
                      constraints.maxWidth < 240 ||
                      MediaQuery.textScalerOf(context).scale(16) >= 24;
                  final image = ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: 88,
                      child: _ProductImage(imageUrl: item.imageUrl),
                    ),
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            image,
                            const SizedBox(height: 12),
                            details,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            image,
                            const SizedBox(width: 12),
                            Expanded(child: details),
                          ],
                        );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatUnit(String unit) => switch (unit.trim().toLowerCase()) {
    'daily' || 'day' => 'วัน',
    'hourly' || 'hour' => 'ชั่วโมง',
    'monthly' || 'month' => 'เดือน',
    'weekly' || 'week' => 'สัปดาห์',
    _ => unit.isEmpty ? '-' : unit,
  };
  static String _priceLabel(double price) => price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(2);
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});
  final String imageUrl;
  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return const _ProductImageFallback();
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const _ProductImageFallback(),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      cacheWidth: 250,
      cacheHeight: 250,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const _ProductImageFallback(showProgress: true),
      errorBuilder: (context, error, stackTrace) =>
          const _ProductImageFallback(),
    );
  }
}

class _ProductImageFallback extends StatelessWidget {
  const _ProductImageFallback({this.showProgress = false});
  final bool showProgress;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ChatbotDesign.subtle,
    child: Center(
      child: showProgress
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ChatbotDesign.primary,
              ),
            )
          : const Icon(
              Icons.inventory_2_outlined,
              color: ChatbotDesign.muted,
              size: 28,
            ),
    ),
  );
}
