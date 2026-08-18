import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/colors.dart';

/// วิดเจ็ตสำหรับรองรับการลากข้อความเพื่อตอบกลับ (Swipe to Reply)
/// - ข้อความตัวเอง (isMine == true): ลากจากขวาไปซ้าย (Drag Left)
/// - ข้อความผู้อื่น (isMine == false): ลากจากซ้ายไปขวา (Drag Right)
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.isMine,
    required this.onReply,
  });

  final Widget child;
  final bool isMine;
  final VoidCallback onReply;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _anim;
  double _dragOffset = 0.0;
  bool _triggeredHaptic = false;

  static const double _triggerThreshold = 44.0;
  static const double _maxDrag = 68.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _anim.value;
        });
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    setState(() {
      if (widget.isMine) {
        // Own message: Drag right to left (negative delta)
        _dragOffset = (_dragOffset + delta).clamp(-_maxDrag, 0.0);
        if (_dragOffset <= -_triggerThreshold && !_triggeredHaptic) {
          HapticFeedback.selectionClick();
          _triggeredHaptic = true;
        } else if (_dragOffset > -_triggerThreshold) {
          _triggeredHaptic = false;
        }
      } else {
        // Other's message: Drag left to right (positive delta)
        _dragOffset = (_dragOffset + delta).clamp(0.0, _maxDrag);
        if (_dragOffset >= _triggerThreshold && !_triggeredHaptic) {
          HapticFeedback.selectionClick();
          _triggeredHaptic = true;
        } else if (_dragOffset < _triggerThreshold) {
          _triggeredHaptic = false;
        }
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.isMine && _dragOffset <= -_triggerThreshold) {
      widget.onReply();
    } else if (!widget.isMine && _dragOffset >= _triggerThreshold) {
      widget.onReply();
    }

    _triggeredHaptic = false;
    _animateBack();
  }

  void _onHorizontalDragCancel() {
    _triggeredHaptic = false;
    _animateBack();
  }

  void _animateBack() {
    _anim = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset.abs() / _triggerThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      child: Stack(
        alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          // Reply icon indicator
          if (_dragOffset != 0.0)
            Positioned(
              right: widget.isMine ? 16 : null,
              left: widget.isMine ? null : 16,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.7 + (0.3 * progress),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.reply_rounded,
                      color: AppColors.primaryColor,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
