import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.onRentPressed,
    this.animateAssistantResponse = false,
    this.onAnimationStarted,
    this.onTextProgress,
    super.key,
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animateAssistantResponse;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onTextProgress;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final bubble = Container(
      key: ValueKey('chat-${message.role.name}-${message.content}'),
      padding: EdgeInsets.fromLTRB(isUser ? 24 : 22, 20, isUser ? 24 : 18, 20),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primaryColor : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isUser ? 34 : 4),
          topRight: Radius.circular(isUser ? 4 : 34),
          bottomLeft: const Radius.circular(34),
          bottomRight: const Radius.circular(34),
        ),
        boxShadow: isUser
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: isUser
          ? Text(message.content, style: _messageStyle(isUser: true))
          : _AnimatedAssistantContent(
              message: message,
              onRentPressed: onRentPressed,
              animate: animateAssistantResponse,
              onAnimationStarted: onAnimationStarted,
              onProgress: onTextProgress,
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
              child: bubble,
            ),
          );
        },
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: message.recommendedItems.isEmpty ? 0.78 : 0.84,
        child: bubble,
      ),
    );
  }

  static TextStyle _messageStyle({required bool isUser}) {
    return TextStyle(
      color: isUser ? Colors.white : const Color(0xFF303033),
      fontSize: 15,
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
  });

  final ChatMessage message;
  final ValueChanged<RecommendedItem> onRentPressed;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  final VoidCallback? onProgress;

  @override
  State<_AnimatedAssistantContent> createState() =>
      _AnimatedAssistantContentState();
}

class _AnimatedAssistantContentState extends State<_AnimatedAssistantContent> {
  Timer? _timer;
  late List<int> _runes;
  int _visibleRuneCount = 0;

  bool get _isComplete => _visibleRuneCount >= _runes.length;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedAssistantContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    _runes = widget.message.content.runes.toList(growable: false);
    if (!widget.animate || _runes.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final visibleText = String.fromCharCodes(_runes.take(_visibleRuneCount));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: widget.message.content,
          child: ExcludeSemantics(
            child: Text(
              visibleText,
              key: ValueKey(
                'chatbot-animated-response-${widget.message.content}',
              ),
              style: ChatMessageBubble._messageStyle(isUser: false),
            ),
          ),
        ),
        if (_isComplete)
          for (final item in widget.message.recommendedItems) ...[
            const SizedBox(height: 16),
            RecommendedItemCard(
              item: item,
              onPressed: () => widget.onRentPressed(item),
            ),
          ],
      ],
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
      key: ValueKey('recommended-item-${item.id ?? item.name}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF0E1FA)),
        boxShadow: const [
          BoxShadow(color: Color(0x2E9B25E8), blurRadius: 18, spreadRadius: 1),
        ],
      ),
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
              'เช่าเลย',
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
