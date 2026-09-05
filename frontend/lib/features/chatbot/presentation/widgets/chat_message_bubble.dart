import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';
import 'interactive_questionnaire_card.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.onRentPressed,
    this.animateAssistantResponse = false,
    this.onAnimationStarted,
    this.onTextProgress,
    this.onEdit,
    this.onLike,
    this.onDislike,
    this.onCopy,
    super.key,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animateAssistantResponse;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onTextProgress;
  final VoidCallback? onEdit;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final bubble = Container(
      key: isUser
          ? ValueKey('chat-user-${message.content}')
          : const ValueKey('chat-assistant-bubble'),
      padding: EdgeInsets.fromLTRB(
        isUser ? 24 : 4,
        isUser ? 20 : 6,
        isUser ? 24 : 4,
        isUser ? 20 : 8,
      ),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primaryColor : Colors.transparent,
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(34),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(34),
                bottomRight: Radius.circular(34),
              )
            : null,
      ),
      child: isUser
          ? Text(message.content, style: _messageStyle(isUser: true))
          : _AnimatedAssistantContent(
              message: message,
              onRentPressed: onRentPressed,
              animate: animateAssistantResponse,
              onAnimationStarted: onAnimationStarted,
              onProgress: onTextProgress,
              onLike: onLike,
              onDislike: onDislike,
              onCopy: onCopy,
            ),
    );

    if (isUser) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.82,
              ),
              child: GestureDetector(onLongPress: onEdit, child: bubble),
            ),
          );
        },
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: 1.0, child: bubble),
    );
  }

  static TextStyle _messageStyle({required bool isUser}) {
    return TextStyle(
      fontFamily: 'Prompt',
      color: isUser ? Colors.white : const Color(0xFF303033),
      fontSize: isUser ? 15 : 14.5,
      height: 1.65,
      fontWeight: FontWeight.w400,
    );
  }
}

class _AnimatedAssistantContent extends StatefulWidget {
  const _AnimatedAssistantContent({
    required this.message,
    required this.onRentPressed,
    required this.animate,
    this.onAnimationStarted,
    this.onProgress,
    this.onLike,
    this.onDislike,
    this.onCopy,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onCopy;

  @override
  State<_AnimatedAssistantContent> createState() =>
      _AnimatedAssistantContentState();
}

class _AnimatedAssistantContentState extends State<_AnimatedAssistantContent> {
  Timer? _timer;
  late List<int> _runes;
  int _visibleRuneCount = 0;

  bool get _isComplete =>
      !widget.message.isStreaming && _visibleRuneCount >= _runes.length;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedAssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isStreaming || oldWidget.message.isStreaming) {
      _timer?.cancel();
      _runes = widget.message.content.runes.toList(growable: false);
      _visibleRuneCount = _runes.length;
      return;
    }
    if (widget.message.questions.any((q) => q.selectedOption != null)) {
      _timer?.cancel();
      _runes = widget.message.content.runes.toList(growable: false);
      _visibleRuneCount = _runes.length;
      return;
    }
    if (oldWidget.message.content != widget.message.content) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    _runes = widget.message.content.runes.toList(growable: false);
    if (widget.message.isStreaming ||
        widget.message.responseDuration != null ||
        widget.message.questions.any((q) => q.selectedOption != null) ||
        !widget.animate ||
        _runes.isEmpty) {
      _visibleRuneCount = _runes.length;
      return;
    }

    _visibleRuneCount = 0;
    widget.onAnimationStarted?.call();

    final runesPerTick = (_runes.length / 80).ceil();
    _timer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        final nextCount = _visibleRuneCount + runesPerTick;
        _visibleRuneCount = nextCount > _runes.length
            ? _runes.length
            : nextCount;
      });
      widget.onProgress?.call();
      if (_isComplete) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 1) return 'ใช้ความคิด 1 วินาที';
    if (seconds < 60) return 'ใช้ความคิด $seconds วินาที';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return 'ใช้ความคิด $m นาที';
    return 'ใช้ความคิด $m นาที $s วินาที';
  }

  static final MarkdownStyleSheet _markdownStyleSheet = MarkdownStyleSheet(
    h1: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.5,
    ),
    h2: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.5,
    ),
    h3: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.6,
    ),
    p: ChatMessageBubble._messageStyle(isUser: false),
    strong: const TextStyle(
      fontFamily: 'Prompt',
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E1B2E),
    ),
    listBullet: const TextStyle(
      color: AppColors.primaryColor,
      fontWeight: FontWeight.w700,
    ),
  );

  static final Map<String, MarkdownElementBuilder> _markdownBuilders = {
    'h1': _HeadingHighlightBuilder(),
    'h2': _HeadingHighlightBuilder(),
    'h3': _HeadingHighlightBuilder(),
  };

  @override
  Widget build(BuildContext context) {
    final visibleText = String.fromCharCodes(_runes.take(_visibleRuneCount));
    final renderMarkdown =
        _isComplete && _containsMarkdown(widget.message.content);
    final responseKey = ValueKey(
      'chatbot-animated-response-${widget.message.id}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message.responseDuration != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: Color(0xFF8E8E93),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _formatDuration(widget.message.responseDuration!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Prompt',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF757575),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: Color(0xFF8E8E93),
                ),
              ],
            ),
          ),
        if (!renderMarkdown)
          Semantics(
            label: widget.message.content,
            child: ExcludeSemantics(
              child: Text(
                visibleText,
                key: responseKey,
                style: ChatMessageBubble._messageStyle(isUser: false),
              ),
            ),
          )
        else
          MarkdownBody(
            key: ValueKey('chatbot-markdown-response-${widget.message.id}'),
            data: _formatMarkdownText(widget.message.content),
            builders: _markdownBuilders,
            styleSheet: _markdownStyleSheet,
          ),
        for (final question in widget.message.questions) ...[
          if (question.selectedOption != null)
            QuestionnaireRecapCard(question: question),
        ],
        if (_isComplete) ...[
          for (final item in widget.message.recommendedItems) ...[
            const SizedBox(height: 16),
            RecommendedItemCard(
              item: item,
              onPressed: () => widget.onRentPressed(item),
            ),
          ],
          if (widget.message.content.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _AssistantActionBar(
              isLiked: widget.message.isLiked,
              onLike: widget.onLike,
              onDislike: widget.onDislike,
              onCopy: widget.onCopy,
            ),
          ],
        ],
      ],
    );
  }

  static String _formatMarkdownText(String text) {
    var formatted = text.replaceAllMapped(
      RegExp(r'(?<=\S)\s*(#{1,4})'),
      (match) => '\n\n${match.group(1)} ',
    );
    formatted = formatted.replaceAllMapped(
      RegExp(r'(#{1,4})([^\s#])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    // Ensure numbered lists (1. 2. 3. or 1) 2) 3)) start on a new line
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|(?<=\S)\s+)(\d+)\)\s*'),
      (match) => '\n\n${match.group(1)}. ',
    );
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?<=\S)\s+(\d+\.\s+)'),
      (match) => '\n\n${match.group(1)}',
    );
    return formatted.trim();
  }

  static bool _containsMarkdown(String text) {
    return text.contains('#') ||
        text.contains('**') ||
        text.contains('* ') ||
        text.contains('- ') ||
        text.contains('```') ||
        RegExp(r'(?:^|\n)\s*\d+\.\s').hasMatch(text);
  }
}

class _HeadingHighlightBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var text = element.textContent.trim();
    if (text.isEmpty) return null;

    if (text.contains('อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด')) {
      text = text.replaceAll(
        'อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด',
        'อุปกรณ์ที่แนะนำ',
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Prompt',
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryColor,
          height: 1.45,
        ),
      ),
    );
  }
}

class RecommendedItemCard extends StatelessWidget {
  const RecommendedItemCard({
    required this.item,
    required this.onPressed,
    super.key,
  });

  final RecommendedItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEDE9FE), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x0C7400C9),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: ValueKey('recommended-item-${item.id ?? item.name}'),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 180) {
                  final imageSize = constraints.maxWidth < 94
                      ? constraints.maxWidth
                      : 94.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(child: _itemImage(imageSize)),
                      const SizedBox(height: 12),
                      _itemDetails(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _itemImage(94),
                    const SizedBox(width: 14),
                    Expanded(child: _itemDetails()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemImage(double dimension) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox.square(
        dimension: dimension,
        child: _ProductImage(imageUrl: item.imageUrl),
      ),
    );
  }

  Widget _itemDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'แนะนำให้เช่า',
          style: TextStyle(
            color: AppColors.primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF2D2D30),
            fontSize: 17,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'ราคาเช่าต่อ${item.unit}\n${_priceLabel(item.price)} ฿',
          style: const TextStyle(
            color: Color(0xFF6E6E73),
            fontSize: 11,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 30,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'รายละเอียด',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  static String _priceLabel(double? price) {
    if (price == null) return '-';
    return price == price.roundToDouble()
        ? price.toInt().toString()
        : price.toStringAsFixed(2);
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return const _ProductImageFallback();

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const _ProductImageFallback(showProgress: true);
      },
      errorBuilder: (context, error, stackTrace) {
        return const _ProductImageFallback();
      },
    );
  }
}

class _ProductImageFallback extends StatelessWidget {
  const _ProductImageFallback({this.showProgress = false});

  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF2F2F4),
      child: Center(
        child: showProgress
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primaryColor,
                size: 34,
              ),
      ),
    );
  }
}

class _AssistantActionBar extends StatelessWidget {
  const _AssistantActionBar({
    required this.isLiked,
    this.onLike,
    this.onDislike,
    this.onCopy,
  });

  final bool? isLiked;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy != null) ...[
            _ActionButton(
              key: const Key('chat-assistant-copy-btn'),
              icon: Icons.content_copy_rounded,
              tooltip: 'คัดลอก',
              onTap: onCopy,
            ),
            const SizedBox(width: 4),
          ],
          _ActionButton(
            key: const Key('chat-assistant-like-btn'),
            icon: isLiked == true
                ? Icons.thumb_up_rounded
                : Icons.thumb_up_outlined,
            color: isLiked == true ? AppColors.primaryColor : null,
            tooltip: 'ถูกใจ',
            onTap: onLike,
          ),
          const SizedBox(width: 4),
          _ActionButton(
            key: const Key('chat-assistant-dislike-btn'),
            icon: isLiked == false
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            color: isLiked == false ? const Color(0xFFEF4444) : null,
            tooltip: 'ไม่ถูกใจ',
            onTap: onDislike,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 16.5,
              color: color ?? const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }
}
