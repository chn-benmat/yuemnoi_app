import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';
import 'interactive_questionnaire_card.dart';
import 'ai_summary_bottom_sheet.dart';
import 'chat_response_label.dart';

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
              onCardRevealed: onCardRevealed,
              onContentRendered: onContentRendered,
              onOptionSelected: onOptionSelected,
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
    this.onCardRevealed,
    this.onContentRendered,
    this.onOptionSelected,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;
  final VoidCallback? onCardRevealed;
  final VoidCallback? onContentRendered;
  final ValueChanged<String>? onOptionSelected;

  @override
  State<_AnimatedAssistantContent> createState() =>
      _AnimatedAssistantContentState();
}

class _AnimatedAssistantContentState extends State<_AnimatedAssistantContent> {
  Timer? _typewriterTimer;
  Timer? _cardStaggerTimer;
  Timer? _statusHeaderTimer;
  DateTime? _fallbackStartTime;
  int _secondsElapsed = 0;
  Characters _targetCharacters = Characters('');
  int _visibleCount = 0;
  int _revealedCardsCount = 0;
  DateTime _lastProgressCall = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isComplete =>
      !widget.message.isStreaming && _visibleCount >= _targetCharacters.length;

  void _updateElapsed() {
    final start = widget.message.createdAt ?? _fallbackStartTime;
    if (start != null) {
      final diff = DateTime.now().difference(start).inSeconds;
      _secondsElapsed = diff > _secondsElapsed ? diff : _secondsElapsed + 1;
    } else {
      _secondsElapsed += 1;
    }
  }

  void _startStatusHeaderTimerIfNeeded() {
    if (_shouldShowStatusHeader && widget.message.responseDuration == null) {
      _statusHeaderTimer ??= Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          _statusHeaderTimer = null;
          return;
        }
        if (widget.message.responseDuration != null ||
            !_shouldShowStatusHeader) {
          timer.cancel();
          _statusHeaderTimer = null;
          return;
        }
        setState(() {
          _updateElapsed();
        });
      });
    } else {
      _statusHeaderTimer?.cancel();
      _statusHeaderTimer = null;
    }
  }

  String _resolveContent() {
    final text = widget.message.content.trim();
    if (text.isNotEmpty) {
      return widget.message.content;
    }
    if (widget.message.isStreaming) return '';
    return 'การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง';
  }

  bool _isTypewriting = false;

  @override
  void initState() {
    super.initState();
    _fallbackStartTime = widget.message.createdAt ?? DateTime.now();
    final start = widget.message.createdAt ?? _fallbackStartTime;
    _secondsElapsed = start != null
        ? math.max(0, DateTime.now().difference(start).inSeconds)
        : 0;
    _startStatusHeaderTimerIfNeeded();
    final effectiveText = _resolveContent();
    _targetCharacters = effectiveText.characters;

    // หากไม่ใช่ข้อความใหม่ที่ต้อง animate หรือเป็นแบบสอบถามที่ตอบแล้ว
    final isNotAnimated =
        !widget.animate || widget.message.understanding != null;
    final hasAnsweredQuestion = widget.message.questions.any(
      (q) => q.selectedOption != null,
    );

    if (isNotAnimated || hasAnsweredQuestion) {
      _visibleCount = _targetCharacters.length;
      _revealedCardsCount = widget.message.recommendedItems.length;
      _isTypewriting = false;
      return;
    }

    _visibleCount = 0;
    _revealedCardsCount = 0;
    _isTypewriting = true;
    widget.onAnimationStarted?.call();

    if (_targetCharacters.isNotEmpty) {
      _startTypewriter();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedAssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.id != oldWidget.message.id ||
        widget.message.createdAt != oldWidget.message.createdAt) {
      _fallbackStartTime = widget.message.createdAt ?? DateTime.now();
      final start = widget.message.createdAt ?? _fallbackStartTime;
      _secondsElapsed = start != null
          ? math.max(0, DateTime.now().difference(start).inSeconds)
          : 0;
    }
    _startStatusHeaderTimerIfNeeded();
    final effectiveText = _resolveContent();
    _targetCharacters = effectiveText.characters;

    // ผลแบบมีโครงสร้างพร้อมแสดง ไม่เพิ่มคิวพิมพ์ดีดหลังบริการตอบครบแล้ว
    if (widget.message.understanding != null ||
        widget.message.questions.any((q) => q.selectedOption != null)) {
      _cardStaggerTimer?.cancel();
      _cardStaggerTimer = null;
      _typewriterTimer?.cancel();
      _typewriterTimer = null;
      _isTypewriting = false;
      _visibleCount = _targetCharacters.length;
      _revealedCardsCount = widget.message.recommendedItems.length;
      return;
    }

    if (_isTypewriting) {
      // อยู่ระหว่างการพิมพ์ดีดแบบ Stream หรือ Animate
      if (_visibleCount < _targetCharacters.length) {
        if (_typewriterTimer == null || !_typewriterTimer!.isActive) {
          _startTypewriter();
        }
      } else if (!widget.message.isStreaming) {
        // สตรีมสิ้นสุดแล้วและพิมพ์จนครบทุกตัวอักษรแล้ว
        _isTypewriting = false;
        _typewriterTimer?.cancel();
        _typewriterTimer = null;
        if (_revealedCardsCount < widget.message.recommendedItems.length) {
          _startCardStagger();
        }
      }
      return;
    }

    if (oldWidget.message.content != widget.message.content) {
      if (widget.animate) {
        _visibleCount = 0;
        _revealedCardsCount = 0;
        _isTypewriting = true;
        widget.onAnimationStarted?.call();
        _startTypewriter();
      } else {
        _visibleCount = _targetCharacters.length;
        _revealedCardsCount = widget.message.recommendedItems.length;
      }
    } else if (oldWidget.message.recommendedItems.length !=
        widget.message.recommendedItems.length) {
      if (!widget.message.isStreaming && !_isTypewriting) {
        _revealedCardsCount = widget.message.recommendedItems.length;
      }
    }
  }

  void _startTypewriter() {
    _typewriterTimer?.cancel();

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 20), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final targetLen = _targetCharacters.length;
      if (_visibleCount >= targetLen) {
        timer.cancel();
        _typewriterTimer = null;
        if (!widget.message.isStreaming) {
          _isTypewriting = false;
          setState(() {
            _visibleCount = targetLen;
          });
          _startCardStagger();
        }
        return;
      }

      // คำนวณ step ในการพิมพ์อย่างนุ่มนวลตามจำนวนตัวอักษรที่ค้างอยู่ (backlog)
      final backlog = targetLen - _visibleCount;
      final int step;
      if (backlog <= 8) {
        step = 1;
      } else if (backlog <= 24) {
        step = 1;
      } else if (backlog <= 60) {
        step = 2;
      } else if (backlog <= 120) {
        step = 3;
      } else {
        step = (backlog / 35).ceil().clamp(3, 8);
      }

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
        _isTypewriting = false;
        _startCardStagger();
      }
    });
  }

  void _startCardStagger() {
    _cardStaggerTimer?.cancel();
    final totalCards = widget.message.recommendedItems.length;
    if (totalCards == 0 || _revealedCardsCount >= totalCards) return;

    _cardStaggerTimer = Timer.periodic(const Duration(milliseconds: 160), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_revealedCardsCount >= totalCards) {
        timer.cancel();
        _cardStaggerTimer = null;
        return;
      }
      setState(() {
        _revealedCardsCount++;
      });
      widget.onProgress?.call();
      widget.onCardRevealed?.call();
    });
  }

  @override
  void dispose() {
    _statusHeaderTimer?.cancel();
    _typewriterTimer?.cancel();
    _cardStaggerTimer?.cancel();
    super.dispose();
  }

  static final MarkdownStyleSheet _markdownStyleSheet = MarkdownStyleSheet(
    h1: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.45,
    ),
    h2: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.45,
    ),
    h3: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryColor,
      height: 1.4,
    ),
    h1Padding: const EdgeInsets.only(top: 12, bottom: 6),
    h2Padding: const EdgeInsets.only(top: 12, bottom: 6),
    h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
    p: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 14,
      height: 1.6,
      color: Color(0xFF1E1B2E),
    ),
    pPadding: const EdgeInsets.only(bottom: 6),
    strong: const TextStyle(
      fontFamily: 'Prompt',
      fontWeight: FontWeight.w700,
      color: Color(0xFF1E1B2E),
    ),
    listBullet: const TextStyle(
      fontFamily: 'Prompt',
      color: AppColors.primaryColor,
      fontWeight: FontWeight.w700,
    ),
    listBulletPadding: const EdgeInsets.only(right: 6),
    listIndent: 16,
    blockSpacing: 8,
    blockquote: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 13.5,
      height: 1.55,
      color: Color(0xFF2E1A58),
      fontWeight: FontWeight.w500,
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0xFFF8F6FD),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: AppColors.primaryColor, width: 3),
      ),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(width: 1, color: Color(0xFFEBE5F7))),
    ),
    tableBorder: TableBorder.all(
      color: const Color(0xFFE0D8F3),
      borderRadius: BorderRadius.circular(8),
    ),
    tableHead: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: Color(0xFF2E1A58),
    ),
    tableBody: const TextStyle(
      fontFamily: 'Prompt',
      fontSize: 13,
      color: Color(0xFF404044),
    ),
    tablePadding: const EdgeInsets.all(8),
  );

  bool get _shouldShowStatusHeader {
    return widget.message.responseDuration != null ||
        (widget.message.userQuery != null &&
            widget.message.userQuery!.isNotEmpty) ||
        widget.message.isStreaming;
  }

  static String _formatSeconds(int seconds) {
    if (seconds < 60) return '$seconds วิ';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m นาที $s วิ';
  }

  String _getCompletedStatusTitle() {
    final status = widget.message.statusMessage;
    if (status != null && status.isNotEmpty && !status.startsWith('กำลัง')) {
      return status;
    }
    return chatResponseLabel(
      widget.message.understanding?.responseKind,
      hasQuestions: widget.message.questions.isNotEmpty,
    );
  }

  Widget _buildStatusHeader() {
    String text;
    if (widget.message.responseDuration != null) {
      final seconds = widget.message.responseDuration!.inSeconds;
      final displaySec = seconds > 0
          ? seconds
          : (widget.message.responseDuration!.inMilliseconds > 0 ? 1 : 0);
      final title = _getCompletedStatusTitle();
      text = '$title (${_formatSeconds(displaySec)})';
    } else {
      final status = widget.message.statusMessage ?? 'กำลังประมวลผล';
      text = '$status (${_formatSeconds(_secondsElapsed)})..';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('chatbot-status-header-button-${widget.message.id}'),
          onTap: () => AISummaryBottomSheet.show(context, widget.message),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    text,
                    key: ValueKey('chatbot-status-header-${widget.message.id}'),
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
                const SizedBox(width: 3),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: Color(0xFF8E8E93),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveText = _resolveContent();
    final visibleText = _targetCharacters.take(_visibleCount).toString();
    final renderMarkdown = _containsMarkdown(effectiveText);
    final responseKey = ValueKey(
      'chatbot-animated-response-${widget.message.id}',
    );

    // ใช้รายการที่ตรวจ ID แล้วโดยตรง ไม่อ่านชื่อสินค้ากลับจากข้อความ
    final itemsToRender = widget.message.recommendedItems;
    if (_isComplete && _revealedCardsCount >= itemsToRender.length) {
      final message = widget.message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(message, widget.message)) {
          widget.onContentRendered?.call();
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_shouldShowStatusHeader) _buildStatusHeader(),
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
            data: visibleText,
            styleSheet: _markdownStyleSheet,
          ),
        if (widget.message.questions.any((q) => q.selectedOption != null))
          QuestionnaireRecapCard(questions: widget.message.questions),
        if (!widget.message.questions.any((q) => q.selectedOption == null) &&
            _isComplete) ...[
          for (var i = 0; i < itemsToRender.length; i++) ...[
            if (i < _revealedCardsCount) ...[
              const SizedBox(height: 16),
              if (widget.message.understanding != null)
                RecommendedItemCard(
                  item: itemsToRender[i],
                  messageContent: effectiveText,
                  onPressed: () => widget.onRentPressed(itemsToRender[i]),
                )
              else
                _AnimatedCardEntrance(
                  key: ValueKey('staggered-card-${widget.message.id}-$i'),
                  child: RecommendedItemCard(
                    item: itemsToRender[i],
                    messageContent: effectiveText,
                    onPressed: () => widget.onRentPressed(itemsToRender[i]),
                  ),
                ),
            ],
          ],
        ],
      ],
    );
  }

  // ตรวจเฉพาะไวยากรณ์แสดงผล ไม่ตีความเจตนาหรือเปลี่ยนข้อมูลสินค้า
  static bool _containsMarkdown(String text) =>
      ['#', '**', '* ', '- ', '>', '`', '|', '[', '. '].any(text.contains);
}

class _AnimatedCardEntrance extends StatefulWidget {
  const _AnimatedCardEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<_AnimatedCardEntrance> createState() => _AnimatedCardEntranceState();
}

class _AnimatedCardEntranceState extends State<_AnimatedCardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
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

  /// คำนวณชื่อสินค้าที่แสดงบนการ์ดให้ตรงกับชื่อรุ่นที่ AI ตอบในข้อความ (Zero-Hardcode Dynamic AI Model Match)
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
                if (constraints.maxWidth < 270) {
                  final imageSize = constraints.maxWidth < 94
                      ? constraints.maxWidth
                      : 94.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _itemImage(imageSize),
                      ),
                      const SizedBox(height: 10),
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
      borderRadius: BorderRadius.circular(14),
      child: SizedBox.square(
        dimension: dimension,
        child: _ProductImage(imageUrl: item.imageUrl),
      ),
    );
  }

  Widget _itemDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 11,
                  color: AppColors.primaryColor,
                ),
                SizedBox(width: 3.5),
                Text(
                  'แนะนำสำหรับคุณ',
                  style: TextStyle(
                    fontFamily: 'Prompt',
                    color: AppColors.primaryColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Prompt',
            color: Color(0xFF1E1B2E),
            fontSize: 14.5,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: item.priceDisplay ?? '${_priceLabel(item.price)} ฿',
                style: const TextStyle(
                  fontFamily: 'Prompt',
                  color: AppColors.primaryColor,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: item.priceDisplay != null
                    ? ''
                    : ' / ${_formatUnit(item.unitDisplay ?? item.unit)}',
                style: const TextStyle(
                  fontFamily: 'Prompt',
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatUnit(String unit) {
    final clean = unit.trim().toLowerCase();
    if (clean == 'daily' || clean == 'day') return 'วัน';
    if (clean == 'hourly' || clean == 'hour') return 'ชั่วโมง';
    if (clean == 'monthly' || clean == 'month') return 'เดือน';
    if (clean == 'weekly' || clean == 'week') return 'สัปดาห์';
    return unit.isEmpty ? '-' : unit;
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
      cacheWidth: 250,
      cacheHeight: 250,
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
