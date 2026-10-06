import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';
import 'interactive_questionnaire_card.dart';
import 'ai_summary_bottom_sheet.dart';
import 'chat_response_label.dart';
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

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final bubble = Container(
      key: isUser
          ? ValueKey('chat-user-${message.content}')
          : const ValueKey('chat-assistant-bubble'),
      padding: EdgeInsets.fromLTRB(
        isUser ? 16 : 0,
        isUser ? 12 : 6,
        isUser ? 16 : 0,
        isUser ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: isUser ? ChatbotDesign.tint : Colors.transparent,
        borderRadius: isUser
            ? const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
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
              onReviseQuery: onReviseQuery,
            ),
    );

    if (isUser) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(onLongPress: onEdit, child: bubble),
                  if (onEdit != null)
                    IconButton(
                      key: ValueKey(
                        'chatbot-message-actions-${message.content}',
                      ),
                      tooltip: 'คัดลอกหรือแก้ไขข้อความ',
                      onPressed: onEdit,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: ChatbotDesign.muted,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: 1, child: bubble),
        );
        return constraints.hasBoundedHeight
            ? SingleChildScrollView(child: content)
            : content;
      },
    );
  }

  static TextStyle _messageStyle({required bool isUser}) {
    return TextStyle(
      fontFamily: 'Prompt',
      color: ChatbotDesign.ink,
      fontSize: 16,
      height: 1.55,
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
    this.onReviseQuery,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;
  final VoidCallback? onCardRevealed;
  final VoidCallback? onContentRendered;
  final ValueChanged<String>? onOptionSelected;
  final VoidCallback? onReviseQuery;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            key: ValueKey('chatbot-status-header-${widget.message.id}'),
            style: ChatbotDesign.body.copyWith(
              fontSize: 13,
              color: ChatbotDesign.muted,
            ),
          ),
          TextButton(
            key: ValueKey('chatbot-status-header-button-${widget.message.id}'),
            onPressed: () => AISummaryBottomSheet.show(context, widget.message),
            style: TextButton.styleFrom(
              minimumSize: ChatbotDesign.button,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('ข้อมูลประกอบคำแนะนำ', textAlign: TextAlign.left),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ],
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
        if (_isComplete &&
            itemsToRender.isEmpty &&
            widget.message.questions.isEmpty &&
            [
              'recommendation',
              'overview',
            ].contains(widget.message.understanding?.responseKind)) ...[
          const SizedBox(height: 16),
          ChatbotStateCard(
            key: const Key('chatbot-empty-results'),
            title: 'ยังไม่พบอุปกรณ์ที่ตรง',
            description: 'ลองปรับงบหรือบอกประเภทอุปกรณ์เพิ่มเติม',
            icon: Icons.search_rounded,
            actionLabel: 'ปรับคำถาม',
            onAction: widget.onReviseQuery,
          ),
        ],
        if (_isComplete)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: widget.message.content),
                );
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
                  );
              },
              style: TextButton.styleFrom(minimumSize: ChatbotDesign.button),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('คัดลอกคำตอบ'),
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    final validId = item.id != null && item.id! > 0;
    final status = item.statusDisplay ?? item.status;
    return Material(
      color: ChatbotDesign.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: ChatbotDesign.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('recommended-item-${item.id ?? item.name}'),
        onTap: validId ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 3,
                  child: _ProductImage(imageUrl: item.imageUrl),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.name,
                style: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: item.priceDisplay ?? '${_priceLabel(item.price)} ฿',
                      style: ChatbotDesign.body.copyWith(
                        color: ChatbotDesign.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.priceDisplay == null)
                      TextSpan(
                        text:
                            ' / ${_formatUnit(item.unitDisplay ?? item.unit)}',
                        style: ChatbotDesign.body.copyWith(
                          color: ChatbotDesign.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (status?.isNotEmpty == true ||
                  item.category?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (status?.isNotEmpty == true)
                      Text(
                        status!,
                        style: ChatbotDesign.body.copyWith(
                          fontSize: 13,
                          color: ChatbotDesign.muted,
                        ),
                      ),
                    if (item.category?.isNotEmpty == true)
                      Text(
                        item.category!,
                        style: ChatbotDesign.body.copyWith(
                          fontSize: 13,
                          color: ChatbotDesign.muted,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: validId ? onPressed : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: ChatbotDesign.button,
                  foregroundColor: ChatbotDesign.primary,
                  side: const BorderSide(color: ChatbotDesign.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: const Text('ดูรายละเอียด', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatUnit(String unit) {
    return switch (unit.trim().toLowerCase()) {
      'daily' || 'day' => 'วัน',
      'hourly' || 'hour' => 'ชั่วโมง',
      'monthly' || 'month' => 'เดือน',
      'weekly' || 'week' => 'สัปดาห์',
      _ => unit.isEmpty ? '-' : unit,
    };
  }

  static String _priceLabel(double? price) => price == null
      ? '-'
      : price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(2);
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return const _ProductImageFallback();
    if (imageUrl.startsWith('assets/'))
      return Image.asset(imageUrl, fit: BoxFit.cover);

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
