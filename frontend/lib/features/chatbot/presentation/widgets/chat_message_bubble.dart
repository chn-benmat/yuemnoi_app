import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
  Timer? _typewriterTimer;
  Characters _targetCharacters = Characters('');
  int _visibleCount = 0;
  DateTime _lastProgressCall = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isComplete =>
      !widget.message.isStreaming && _visibleCount >= _targetCharacters.length;

  String _resolveContent() {
    final text = widget.message.content.trim();
    if (text.isNotEmpty || widget.message.isStreaming) {
      return widget.message.content;
    }
    if (widget.message.questions.isNotEmpty) {
      return 'เพื่อช่วยแนะนำอุปกรณ์ที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊';
    }
    if (widget.message.recommendedItems.isNotEmpty) {
      return 'นี่คืออุปกรณ์ที่เราแนะนำสำหรับคุณค่ะ:';
    }
    return 'ขออภัยด้วยนะคะ ขณะนี้ระบบไม่สามารถประมวลผลคำตอบได้ กรุณาลองใหม่อีกครั้งค่ะ';
  }

  @override
  void initState() {
    super.initState();
    final effectiveText = _resolveContent();
    _targetCharacters = effectiveText.characters;

    if (widget.message.isStreaming ||
        widget.message.responseDuration != null ||
        widget.message.questions.any((q) => q.selectedOption != null) ||
        !widget.animate ||
        _targetCharacters.isEmpty) {
      _visibleCount = _targetCharacters.length;
      return;
    }

    _visibleCount = 0;
    widget.onAnimationStarted?.call();
    _startTypewriter();
  }

  @override
  void didUpdateWidget(covariant _AnimatedAssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final effectiveText = _resolveContent();
    _targetCharacters = effectiveText.characters;

    if (widget.message.isStreaming || oldWidget.message.isStreaming) {
      _typewriterTimer?.cancel();
      _typewriterTimer = null;
      _visibleCount = _targetCharacters.length;
      return;
    }

    if (widget.message.questions.any((q) => q.selectedOption != null)) {
      _typewriterTimer?.cancel();
      _typewriterTimer = null;
      _visibleCount = _targetCharacters.length;
      return;
    }

    if (oldWidget.message.content != widget.message.content) {
      if (widget.animate && widget.message.responseDuration == null) {
        _visibleCount = 0;
        widget.onAnimationStarted?.call();
        _startTypewriter();
      } else {
        _visibleCount = _targetCharacters.length;
      }
    }
  }

  void _startTypewriter() {
    _typewriterTimer?.cancel();

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 26), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final targetLen = _targetCharacters.length;
      if (_visibleCount >= targetLen) {
        timer.cancel();
        _typewriterTimer = null;
        setState(() {
          _visibleCount = targetLen;
        });
        return;
      }

      final step = (targetLen / 80).ceil().clamp(1, 4);
      setState(() {
        final next = _visibleCount + step;
        _visibleCount = next > targetLen ? targetLen : next;
      });

      final now = DateTime.now();
      if (now.difference(_lastProgressCall).inMilliseconds >= 60) {
        _lastProgressCall = now;
        widget.onProgress?.call();
      }
      if (_isComplete) {
        timer.cancel();
        _typewriterTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
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
    h1Padding: const EdgeInsets.only(top: 14, bottom: 8),
    h2Padding: const EdgeInsets.only(top: 14, bottom: 8),
    h3Padding: const EdgeInsets.only(top: 14, bottom: 8),
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

  static final _headingWithoutLeadingNewlines = RegExp(r'(?<=\S)\s*(#{1,4})');
  static final _headingMissingSpace = RegExp(r'(#{1,4})([^\s#])');
  static final _numberedListParen = RegExp(r'(?:^|(?<=\S)\s+)(\d+)\)\s*');
  static final _numberedListSpace = RegExp(r'(?<=\S)\s+(\d+\.\s+)');
  static final _numberedListPattern = RegExp(r'(?:^|\n)\s*\d+\.\s');

  static final _codeBlockRegex = RegExp(r'```');
  static final _inlineCodeRegex = RegExp(r'(?<!`)`(?!`)');
  static final _boldRegex = RegExp(r'\*\*');
  static final _tripleUnderscoreRegex = RegExp(r'___');
  static final _doubleUnderscoreRegex = RegExp(r'__');

  static String _sanitizePartialMarkdown(String text) {
    if (text.isEmpty) return text;
    var sanitized = text;

    final codeBlockMatches = _codeBlockRegex.allMatches(sanitized).length;
    if (codeBlockMatches.isOdd) {
      return '$sanitized\n```';
    }

    final inlineCodeMatches = _inlineCodeRegex.allMatches(sanitized).length;
    if (inlineCodeMatches.isOdd) {
      sanitized += '`';
      return sanitized;
    }

    final boldMatches = _boldRegex.allMatches(sanitized).length;
    if (boldMatches.isOdd) {
      sanitized += '**';
    }

    final tripleUnderscoreMatches =
        _tripleUnderscoreRegex.allMatches(sanitized).length;
    if (tripleUnderscoreMatches.isOdd) {
      sanitized += '___';
    } else {
      final doubleUnderscoreMatches =
          _doubleUnderscoreRegex.allMatches(sanitized).length;
      if (doubleUnderscoreMatches.isOdd) {
        sanitized += '__';
      }
    }

    return sanitized;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveText = _resolveContent();
    if (_targetCharacters.isEmpty && effectiveText.isNotEmpty) {
      _targetCharacters = effectiveText.characters;
      _visibleCount = _targetCharacters.length;
    }
    final visibleText = _targetCharacters.take(_visibleCount).toString();
    final renderMarkdown = _containsMarkdown(effectiveText);
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
            label: effectiveText,
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
            data: _formatMarkdownText(_sanitizePartialMarkdown(visibleText)),
            styleSheet: _markdownStyleSheet,
          ),
        for (final question in widget.message.questions) ...[
          if (question.selectedOption != null)
            QuestionnaireRecapCard(question: question),
        ],
        if (_isComplete &&
            !widget.message.questions.any((q) => q.selectedOption == null)) ...[
          for (final item in widget.message.recommendedItems) ...[
            const SizedBox(height: 16),
            RecommendedItemCard(
              item: item,
              onPressed: () => widget.onRentPressed(item),
            ),
          ],
          if (effectiveText.trim().isNotEmpty) ...[
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
      _headingWithoutLeadingNewlines,
      (match) => '\n\n${match.group(1)} ',
    );
    formatted = formatted.replaceAllMapped(
      _headingMissingSpace,
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    // Ensure numbered lists (1. 2. 3. or 1) 2) 3)) start on a new line
    formatted = formatted.replaceAllMapped(
      _numberedListParen,
      (match) => '\n\n${match.group(1)}. ',
    );
    formatted = formatted.replaceAllMapped(
      _numberedListSpace,
      (match) => '\n\n${match.group(1)}',
    );
    if (formatted.contains('อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด')) {
      formatted = formatted.replaceAll(
        'อุปกรณ์แนะนำที่ตอบโจทย์ที่สุด',
        'อุปกรณ์ที่แนะนำ',
      );
    }
    return formatted.trim();
  }

  static bool _containsMarkdown(String text) {
    return text.contains('#') ||
        text.contains('**') ||
        text.contains('* ') ||
        text.contains('- ') ||
        text.contains('```') ||
        _numberedListPattern.hasMatch(text);
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
