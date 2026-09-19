import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';
import 'interactive_questionnaire_card.dart';
import 'ai_summary_bottom_sheet.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.onRentPressed,
    this.animateAssistantResponse = false,
    this.onAnimationStarted,
    this.onTextProgress,
    this.onCardRevealed,
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
    this.onOptionSelected,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;
  final VoidCallback? onCardRevealed;
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
      if (_statusHeaderTimer == null) {
        _statusHeaderTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            _statusHeaderTimer = null;
            return;
          }
          if (widget.message.responseDuration != null || !_shouldShowStatusHeader) {
            timer.cancel();
            _statusHeaderTimer = null;
            return;
          }
          setState(() {
            _updateElapsed();
          });
        });
      }
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
    final isNotAnimated = !widget.animate;
    final hasAnsweredQuestion =
        widget.message.questions.any((q) => q.selectedOption != null);

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

    // หากมีการเลือกตัวเลือกในแบบสอบถามแล้ว ให้หยุด typewriter และแสดงทั้งหมดทันที
    if (widget.message.questions.any((q) => q.selectedOption != null)) {
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
        left: BorderSide(
          color: AppColors.primaryColor,
          width: 3,
        ),
      ),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(
        top: BorderSide(
          width: 1,
          color: Color(0xFFEBE5F7),
        ),
      ),
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

  static final _headingWithoutLeadingNewlines = RegExp(r'(?<=\S)\s*(#{1,4})');
  static final _headingMissingSpace = RegExp(r'(#{1,4})([^\s#])');
  static final _numberedListParen = RegExp(r'(?:^|(?<=[.!?:\n])\s*)(\d+)\)\s*');
  static final _numberedListSpace = RegExp(r'(?<=[.!?:\n])\s+(\d+\.\s+)');
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

    final tripleUnderscoreMatches = _tripleUnderscoreRegex
        .allMatches(sanitized)
        .length;
    if (tripleUnderscoreMatches.isOdd) {
      sanitized += '___';
    } else {
      final doubleUnderscoreMatches = _doubleUnderscoreRegex
          .allMatches(sanitized)
          .length;
      if (doubleUnderscoreMatches.isOdd) {
        sanitized += '__';
      }
    }

    return sanitized;
  }

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
    if (status != null &&
        status.isNotEmpty &&
        !status.startsWith('กำลัง')) {
      return status;
    }
    if (widget.message.questions.isNotEmpty) {
      return 'สอบถามข้อมูลเพิ่มเติม';
    }
    if (widget.message.searchQuery != null && widget.message.searchQuery!.isNotEmpty) {
      return 'ผลการเปรียบเทียบ';
    }
    return 'สรุปคำแนะนำ';
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

    final matchingItems = widget.message.recommendedItems.where((item) {
      return RecommendedItemCard.isItemMentioned(item.name, effectiveText);
    }).toList();
    final itemsToRender = matchingItems;

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
            data: _formatMarkdownText(_sanitizePartialMarkdown(visibleText)),
            styleSheet: _markdownStyleSheet,
          ),
        if (widget.message.questions.any((q) => q.selectedOption != null))
          QuestionnaireRecapCard(questions: widget.message.questions),
        if (!widget.message.questions.any((q) => q.selectedOption == null) && _isComplete) ...[
          for (var i = 0; i < itemsToRender.length; i++) ...[
            if (i < _revealedCardsCount) ...[
              const SizedBox(height: 16),
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

  static String _formatMarkdownText(String text) {
    var formatted = text;
    // Convert HTML tags (like <strong>...</strong> or <b>...</b>) to Markdown (**...**)
    formatted = formatted.replaceAllMapped(
      RegExp(
        r'<\s*(?:strong|b)\s*>(.*?)<\s*/\s*(?:strong|b)\s*>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) => '**${match.group(1)}**',
    );
    // Normalize markdown bold with inner whitespace: "** text **" -> "**text**"
    formatted = formatted.replaceAllMapped(
      RegExp(r'\*\*\s*([^*\n]+?)\s*\*\*'),
      (match) => '**${match.group(1)?.trim()}**',
    );
    formatted = formatted.replaceAll(
      RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false),
      '\n',
    );
    formatted = formatted.replaceAll(
      RegExp(r'</?(?:strong|b|span|p|div|li|ul|ol)>', caseSensitive: false),
      '',
    );
    // If the message contains "ชื่ออุปกรณ์: [ชื่อ]", remove "ชื่ออุปกรณ์:" and make the device name bold: **[ชื่อ]**
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*(?:\*\*)?\s*ชื่ออุปกรณ์\s*[:：]\s*(?:\*\*)?\s*([^\n]+)', caseSensitive: false),
      (match) {
        final deviceName = match.group(1)?.replaceAll('*', '').trim() ?? '';
        return deviceName.isNotEmpty ? '\n\n**$deviceName**' : '';
      },
    );
    // Ensure property labels have clean opening and closing asterisks: - **รายละเอียด:**, - **ราคาเช่า:**
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[-•●*]?\s*(?:\*\*)?\s*รายละเอียด\s*(?:\*\*)?\s*[:：]\s*(?:\*\*)?\s*', caseSensitive: false),
      (match) => '\n- **รายละเอียด:** ',
    );
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[-•●*]?\s*(?:\*\*)?\s*(?:ราคาเช่า|ค่าเช่า)\s*(?:\*\*)?\s*[:：]\s*(?:\*\*)?\s*', caseSensitive: false),
      (match) => '\n- **ราคาเช่า:** ',
    );
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[-•●*]?\s*(?:\*\*)?\s*เหมาะสำหรับ\s*(?:\*\*)?\s*[:：]\s*(?:\*\*)?\s*', caseSensitive: false),
      (match) => '\n- **เหมาะสำหรับ:** ',
    );
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[-•●*]?\s*(?:\*\*)?\s*จุดเด่น\s*(?:\*\*)?\s*[:：]\s*(?:\*\*)?\s*', caseSensitive: false),
      (match) => '\n- **จุดเด่น:** ',
    );

    // Format units to Thai "บาท ต่อ วัน" / "บาท ต่อ ชั่วโมง"
    formatted = formatted.replaceAll(RegExp(r'(?:บาท\s*/\s*daily|บาท\s+ต่อ\s+daily)', caseSensitive: false), 'บาท ต่อ วัน');
    formatted = formatted.replaceAll(RegExp(r'(?:บาท\s*/\s*hourly|บาท\s+ต่อ\s+hourly)', caseSensitive: false), 'บาท ต่อ ชั่วโมง');
    formatted = formatted.replaceAll(RegExp(r'(?:บาท\s*/\s*weekly|บาท\s+ต่อ\s+weekly)', caseSensitive: false), 'บาท ต่อ สัปดาห์');
    formatted = formatted.replaceAll(RegExp(r'(?:บาท\s*/\s*monthly|บาท\s+ต่อ\s+monthly)', caseSensitive: false), 'บาท ต่อ เดือน');
    formatted = formatted.replaceAll(RegExp(r'บาท\s*/\s*วัน', caseSensitive: false), 'บาท ต่อ วัน');
    formatted = formatted.replaceAll(RegExp(r'บาท\s*/\s*ชั่วโมง', caseSensitive: false), 'บาท ต่อ ชั่วโมง');

    // Remove redundant .0 decimal from prices (e.g. 850.0 บาท -> 850 บาท)
    formatted = formatted.replaceAllMapped(
      RegExp(r'(\d+)\.0(?=\s*บาท|\s+ต่อ)', caseSensitive: false),
      (match) => match.group(1)!,
    );

    // If a bullet item starts with a device emoji/icon, convert it to a Heading 3 so it renders in app purple without a bullet
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[-•●*]\s*(?=[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}])', unicode: true),
      (match) => '\n\n### ',
    );

    // Convert unicode bullets into standard markdown list items
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?:^|\n)\s*[•●]\s*'),
      (match) => '\n- ',
    );

    formatted = formatted.replaceAllMapped(
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
    // Ensure blockquotes (> ...) start on a new line if preceded by non-newline characters
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?<=\S)\s*(>[^\n]*)'),
      (match) => '\n\n${match.group(1)}',
    );
    return formatted.trim();
  }

  static bool _containsMarkdown(String text) {
    return text.contains('#') ||
        text.contains('**') ||
        text.contains('* ') ||
        text.contains('- ') ||
        text.contains('•') ||
        text.contains('>') ||
        text.contains('<strong') ||
        text.contains('<b>') ||
        text.contains('```') ||
        text.contains('|') ||
        text.contains('เหมาะสำหรับ') ||
        text.contains('จุดเด่น') ||
        text.contains('ค่าเช่า') ||
        _numberedListPattern.hasMatch(text);
  }
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
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
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
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
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

  /// คำนวณชื่อสินค้าที่แสดงบนการ์ดให้ตรงกับชื่อรุ่นที่ AI ตอบในข้อความ (Zero-Hardcode Dynamic AI Model Match)
  static String resolveItemDisplayName(String catalogName, String? messageContent) {
    if (messageContent == null || messageContent.isEmpty || catalogName.isEmpty) {
      return catalogName;
    }

    // 0. ตรวจสอบบรรทัด **ชื่ออุปกรณ์:** ... หรือ **ชื่ออุปกรณ์: ...** โดยตรง
    final deviceLineRegex = RegExp(
      r'(?:^|\n)\s*(?:\*\*)?\s*ชื่ออุปกรณ์\s*[:：]\s*(?:\*\*)?\s*([^\n]+)',
      caseSensitive: false,
    );
    for (final match in deviceLineRegex.allMatches(messageContent)) {
      var candidate = match.group(1)?.trim() ?? '';
      candidate = candidate.replaceAll(RegExp(r'\*+'), '').trim();
      if (candidate.isEmpty) continue;

      final lowerCatalog = catalogName.toLowerCase();
      final lowerCandidate = candidate.toLowerCase();

      if (lowerCatalog == lowerCandidate ||
          (lowerCatalog.contains(lowerCandidate) && lowerCandidate.length >= 3) ||
          (lowerCandidate.contains(lowerCatalog) && lowerCatalog.length >= 3)) {
        return candidate;
      }

      final catalogWords = lowerCatalog.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();
      final candidateWords = lowerCandidate.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();
      final intersection = catalogWords.intersection(candidateWords);
      if (intersection.length >= 2 && intersection.length >= (candidateWords.length * 0.6)) {
        return candidate;
      }
    }

    // 1. ตรวจจับชื่อรุ่นในรูปแบบ Markdown Bold: **...** ที่ AI สกัดมา
    final boldMatches = RegExp(r'\*\*\s*([^*\n]+?)\s*\*+').allMatches(messageContent);
    for (final m in boldMatches) {
      final rawCandidate = m.group(1)?.trim();
      if (rawCandidate == null || rawCandidate.isEmpty) continue;

      // กรองคำทั่วไปที่ไม่ใช่ชื่อสินค้า เช่น หัวข้อสรุปหรือคำแนะนำ
      if (rawCandidate.contains('สรุป') ||
          rawCandidate.contains('คำแนะนำ') ||
          rawCandidate.contains('ค้นหา') ||
          rawCandidate.contains('เปรียบเทียบ') ||
          rawCandidate.contains('ข้อควรระวัง') ||
          rawCandidate.contains('จุดเด่น') ||
          rawCandidate.contains('หน้าจอ') ||
          rawCandidate.contains('ประสิทธิภาพ') ||
          rawCandidate.contains('หน่วยความจำ') ||
          rawCandidate.contains('รายละเอียด') ||
          rawCandidate.contains('ราคาเช่า') ||
          rawCandidate.contains('ความคล่องตัว')) {
        continue;
      }

      // ตัด prefix เช่น "ชื่ออุปกรณ์: " ออกถ้ามี
      final candidate = rawCandidate.replaceFirst(RegExp(r'^(?:ชื่ออุปกรณ์|อุปกรณ์)\s*[:：]\s*'), '').trim();
      if (candidate.isEmpty) continue;

      final lowerCatalog = catalogName.toLowerCase();
      final lowerCandidate = candidate.toLowerCase();

      // 1.1 ตรงกันทั้งหมด (Exact match)
      if (lowerCatalog == lowerCandidate) {
        return candidate;
      }

      // 1.2 ชื่อที่ AI ตอบเป็นส่วนหนึ่งของชื่อเต็มในระบบ (Substring match)
      // เช่น "PlayStation 5" ใน "PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น"
      // หรือ "Nintendo Switch OLED" ใน "Nintendo Switch OLED พร้อมจอย 4 ตัว"
      // หรือ "Dell UltraSharp 27 นิ้ว 4K" ใน "จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K"
      if (lowerCatalog.contains(lowerCandidate) && lowerCandidate.length >= 3) {
        return candidate;
      }

      // 1.3 ชื่อในระบบเป็นส่วนหนึ่งของชื่อที่ AI ตอบ
      if (lowerCandidate.contains(lowerCatalog) && lowerCatalog.length >= 3) {
        return candidate;
      }

      // 1.4 เปรียบเทียบคำสำคัญ (Word Token Overlap)
      final catalogWords = lowerCatalog.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();
      final candidateWords = lowerCandidate.split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();
      final intersection = catalogWords.intersection(candidateWords);
      if (intersection.length >= 2 && intersection.length >= (candidateWords.length * 0.6)) {
        return candidate;
      }
    }

    return catalogName;
  }

  /// ตรวจสอบว่าอุปกรณ์ถูกระบุถึงหรือแนะนำในข้อความ AI หรือไม่ เพื่อให้การ์ดตรงกับข้อความ 100%
  static bool isItemMentioned(String catalogName, String? messageContent) {
    if (messageContent == null || messageContent.trim().isEmpty || catalogName.isEmpty) {
      return false;
    }
    final resolved = resolveItemDisplayName(catalogName, messageContent);
    final lowerCatalog = catalogName.toLowerCase();
    final lowerContent = messageContent.toLowerCase();

    // 1. ถ้า resolveItemDisplayName สกัดชื่อเฉพาะที่ตรงกับ Markdown Bold หรือบรรทัดชื่ออุปกรณ์ในข้อความมาได้
    if (resolved != catalogName && lowerContent.contains(resolved.toLowerCase())) {
      return true;
    }

    // 2. ชื่อเต็มของอุปกรณ์ปรากฏในข้อความโดยตรง
    if (lowerContent.contains(lowerCatalog)) {
      return true;
    }

    // 3. ตรวจสอบคำสำคัญ/ชื่อรุ่น ในบรรทัดที่มีการแนะนำ (Bullet point หรือ บรรทัดชื่ออุปกรณ์)
    final words = lowerCatalog
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !RegExp(r'^\d+$').hasMatch(w) && !['เครื่อง', 'สำหรับ', 'พร้อม', 'ชุด', 'ขนาด'].contains(w))
        .toList();
    for (final line in messageContent.split('\n')) {
      final lineTrim = line.trim();
      if (lineTrim.startsWith('•') ||
          lineTrim.startsWith('-') ||
          lineTrim.startsWith('*') ||
          lineTrim.contains('ชื่ออุปกรณ์')) {
        final lineLower = lineTrim.toLowerCase();
        final matched = words.where((w) => lineLower.contains(w)).toList();
        if (matched.length >= 2 || (words.length == 1 && matched.length == 1)) {
          return true;
        }
      }
    }

    return false;
  }

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
          resolveItemDisplayName(item.name, messageContent),
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
                text: '${_priceLabel(item.price)} ฿',
                style: const TextStyle(
                  fontFamily: 'Prompt',
                  color: AppColors.primaryColor,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: ' / ${_formatUnit(item.unit)}',
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
    return unit.isEmpty ? 'วัน' : unit;
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
