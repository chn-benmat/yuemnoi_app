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
    this.inlineHeader = false,
    super.key,
  });
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool inlineHeader;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ChatbotDesign.subtle,
      borderRadius: BorderRadius.circular(ChatbotDesign.radius),
      border: Border.all(color: ChatbotDesign.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inlineHeader)
          Row(
            children: [
              CircleAvatar(
                backgroundColor: ChatbotDesign.surface,
                child: Icon(icon, color: ChatbotDesign.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: ChatbotDesign.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: CircleAvatar(
              backgroundColor: ChatbotDesign.surface,
              child: Icon(icon, color: ChatbotDesign.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: ChatbotDesign.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          description,
          style: ChatbotDesign.body.copyWith(
            color: ChatbotDesign.muted,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onAction,
          style: OutlinedButton.styleFrom(
            foregroundColor: ChatbotDesign.primary,
            side: const BorderSide(color: ChatbotDesign.border),
            minimumSize: ChatbotDesign.button,
            shape: ChatbotDesign.buttonShape,
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
    this.now = DateTime.now,
    super.key,
  });
  final ChatbotFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onRevise;
  final DateTime Function() now;

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
    if (deadline == null || !widget.now().isBefore(deadline)) return;
    // คำนวณจากเวลาปลดล็อกเดิมทุกครั้ง เพื่อไม่เริ่มนับใหม่เมื่อวาดหน้าจอซ้ำ
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !widget.now().isBefore(deadline)) timer.cancel();
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
    final now = widget.now();
    final canRetry = failure.canRetry(now);
    final remaining = failure.retryAvailableAt?.difference(now);
    final remainingSeconds = remaining == null || remaining.isNegative
        ? 0
        : (remaining.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    final minutes = remainingSeconds ~/ Duration.secondsPerMinute;
    final seconds = (remainingSeconds % Duration.secondsPerMinute)
        .toString()
        .padLeft(2, '0');
    return ChatbotStateCard(
      key: const Key('chatbot-failure-card'),
      inlineHeader:
          failure.isQuota || failure.errorCode == 'structured_output_invalid',
      title: switch (failure.errorCode) {
        'quota_exhausted' => 'โควต้ารายวันของผู้ช่วย AI ไม่เพียงพอ',
        'quota_temporarily_unavailable' => 'ผู้ช่วย AI ติดโควต้าชั่วคราว',
        'providers_busy' => 'ผู้ช่วย AI ติดคิวชั่วคราว',
        'review_unavailable' => 'ผู้ช่วย AI ยังตรวจสอบคำตอบไม่ได้',
        'structured_output_invalid' => 'ยืมหน่อย สร้างคำตอบไม่ได้',
        'response_quality_rejected' =>
          'คำตอบของผู้ช่วย AI ยังไม่ผ่านการตรวจสอบ',
        _ => failure.isQuota ? 'ผู้ช่วย AI ติดโควต้า' : 'ส่งคำขอไม่สำเร็จ',
      },
      description: failure.message,
      icon: switch (failure.errorCode) {
        'structured_output_invalid' => Icons.data_object_rounded,
        'response_quality_rejected' => Icons.rule_rounded,
        _ =>
          failure.isQuota || failure.errorCode == 'providers_busy'
              ? Icons.schedule_rounded
              : Icons.wifi_off_rounded,
      },
      actionLabel: !failure.isRetryable
          ? 'ปรับคำถาม'
          : remainingSeconds > 0
          ? 'ลองอีกครั้ง ($minutes:$seconds)'
          : 'ลองอีกครั้ง',
      onAction: failure.isRetryable
          ? (canRetry ? widget.onRetry : null)
          : widget.onRevise,
    );
  }
}
