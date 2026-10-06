import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/entities/chatbot_failure.dart';
import 'chatbot_design.dart';

class ChatbotStateCard extends StatelessWidget {
  const ChatbotStateCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    this.onAction,
    super.key,
  });
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ChatbotDesign.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: ChatbotDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CircleAvatar(
            backgroundColor: ChatbotDesign.tint,
            child: Icon(icon, color: ChatbotDesign.primary),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: ChatbotDesign.body.copyWith(color: ChatbotDesign.muted),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            backgroundColor: ChatbotDesign.primary,
            minimumSize: ChatbotDesign.button,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(actionLabel, textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}

class ChatbotFailureCard extends StatefulWidget {
  const ChatbotFailureCard({
    required this.failure,
    required this.onRetry,
    required this.onRevise,
    super.key,
  });
  final ChatbotFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onRevise;

  @override
  State<ChatbotFailureCard> createState() => _ChatbotFailureCardState();
}

class _ChatbotFailureCardState extends State<ChatbotFailureCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ChatbotFailureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.failure != widget.failure) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final deadline = widget.failure.retryAvailableAt;
    if (deadline == null || !DateTime.now().isBefore(deadline)) return;
    // ปลุกปุ่มเมื่อถึงเวลาจริง โดยไม่สร้างตัวเลขนับถอยหลังขึ้นเอง
    _timer = Timer(deadline.difference(DateTime.now()), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final canRetry = failure.canRetry(DateTime.now());
    return ChatbotStateCard(
      key: const Key('chatbot-failure-card'),
      title: failure.isQuota
          ? 'ผู้ช่วย AI ถึงโควตาชั่วคราว'
          : 'ส่งคำขอไม่สำเร็จ',
      description: failure.message,
      icon: failure.isQuota ? Icons.schedule_rounded : Icons.wifi_off_rounded,
      actionLabel: failure.isRetryable ? 'ลองอีกครั้ง' : 'ปรับคำถาม',
      onAction: failure.isRetryable
          ? (canRetry ? widget.onRetry : null)
          : widget.onRevise,
    );
  }
}
