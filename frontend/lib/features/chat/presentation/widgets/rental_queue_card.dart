import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/rental_queue_card_data.dart';

class RentalQueueCard extends StatefulWidget {
  const RentalQueueCard({
    super.key,
    required this.data,
    required this.isOwner,
    required this.onAction,
    this.canJoin = true,
    this.onSendRequest,
  });

  final RentalQueueCardData data;
  final bool isOwner;
  final Future<void> Function(String action)? onAction;
  final bool canJoin;
  final VoidCallback? onSendRequest;

  @override
  State<RentalQueueCard> createState() => _RentalQueueCardState();
}

class _RentalQueueCardState extends State<RentalQueueCard> {
  bool _busy = false;

  Future<void> _perform(String action) async {
    setState(() => _busy = true);
    try {
      await widget.onAction?.call(action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final owner = widget.isOwner;
    final waiting = data.position == null
        ? 'รออุปกรณ์คืน'
        : 'รออุปกรณ์คืน · คิวที่ ${data.position}';
    final text = switch (data.status) {
      RentalQueueStatus.invited =>
        owner ? 'รอผู้เช่าเข้าคิว' : 'เจ้าของชวนคุณเข้าคิว',
      RentalQueueStatus.waiting => waiting,
      RentalQueueStatus.paused => 'อุปกรณ์พักให้เช่าชั่วคราว',
      RentalQueueStatus.ready =>
        owner ? 'กันอุปกรณ์ให้คิวนี้แล้ว' : 'อุปกรณ์พร้อมให้เช่าต่อ',
      RentalQueueStatus.accepted =>
        owner ? 'ผู้เช่ายืนยันสิทธิ์แล้ว' : 'ยืนยันสิทธิ์แล้ว · ส่งคำขอเช่าได้',
      RentalQueueStatus.booked => 'จองเช่าสำเร็จ',
      RentalQueueStatus.left => 'ออกจากคิวแล้ว',
      RentalQueueStatus.expired => 'หมดเวลายืนยันการเช่า',
    };
    final canLeave =
        !owner &&
        switch (data.status) {
          RentalQueueStatus.waiting ||
          RentalQueueStatus.paused ||
          RentalQueueStatus.ready ||
          RentalQueueStatus.accepted => true,
          _ => false,
        };
    final String? action = switch (data.status) {
      RentalQueueStatus.invited when !owner && widget.canJoin => 'join',
      RentalQueueStatus.ready when !owner => 'accept',
      _ => null,
    };
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final numberFormat = NumberFormat.decimalPattern();
    return Container(
      constraints: const BoxConstraints(maxWidth: 284),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'คิวเช่าต่อ',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(data.name, style: Theme.of(context).textTheme.titleMedium),
          if (data.displayRates.hourly case final hourly?)
            Text('${numberFormat.format(hourly)} บาท / ชั่วโมง'),
          if (data.displayRates.daily case final daily?)
            Text('${numberFormat.format(daily)} บาท / วัน'),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (data.dueAt case final due?)
            Text('กำหนดคืนโดยประมาณ ${date.format(due.toLocal())}'),
          if (data.expiresAt case final expires?)
            Text('ยืนยันการเช่าภายใน ${date.format(expires.toLocal())} น.'),
          if (action != null && widget.onAction != null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : () => _perform(action),
              child: Text(
                action == 'join' ? 'ขอคิวเช่าต่อ' : 'ยืนยันสิทธิ์และนัดรับ',
              ),
            ),
          if (!owner &&
              data.status == RentalQueueStatus.accepted &&
              widget.onSendRequest != null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: widget.onSendRequest,
              child: const Text('ส่งคำขอเช่า'),
            ),
          if (canLeave && widget.onAction != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
              ),
              onPressed: _busy ? null : () => _perform('leave'),
              child: const Text('ออกจากคิว'),
            ),
        ],
      ),
    );
  }
}
