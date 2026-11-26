import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/services/app_notification_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../bloc/notification_cubit.dart';

class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key, this.service});

  final AppNotificationService? service;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final injectedService = service;
      if (injectedService != null) {
        return NotificationCubit(injectedService)..refresh();
      }
      final session = AppNotificationService.instance;
      return NotificationCubit(
        AppNotificationService.history()..onOpen = session.onOpen,
        sessionSource: session,
      );
    },
    child: const _NotificationView(),
  );
}

class _NotificationView extends StatelessWidget {
  const _NotificationView();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: const Text(
              'การแจ้งเตือน',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<NotificationCubit, NotificationInboxState>(
              builder: (context, state) {
                final cubit = context.read<NotificationCubit>();
                final visibleItems = state.visibleItems;
                return RefreshIndicator(
                  color: AppColors.primaryColor,
                  backgroundColor: Colors.white,
                  onRefresh: cubit.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 110),
                    children: [
                      if (state.error != null) ...[
                        _Notice(
                          key: const ValueKey('notification-error'),
                          title: state.error!,
                          actionLabel: 'ลองใหม่',
                          onAction: cubit.refresh,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!state.isAuthenticated)
                        const _Notice(
                          title: 'เข้าสู่ระบบเพื่อดูการแจ้งเตือน',
                          subtitle: 'สถานะการเช่าและข้อมูลบัญชีจะแสดงที่นี่',
                        )
                      else ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: state.unreadCount == 0
                                ? null
                                : () async {
                                    try {
                                      await cubit.markAllRead();
                                      if (!context.mounted) return;
                                    } catch (_) {
                                      // สถานะผิดพลาดแสดงจาก Cubit โดยไม่แสร้งว่าอ่านสำเร็จ
                                    }
                                  },
                            child: const Text('อ่านทั้งหมด'),
                          ),
                        ),
                        for (final category in const [
                          AppNotificationCategory.rental,
                          AppNotificationCategory.app,
                        ]) ...[
                          _NotificationSection(
                            category: category,
                            items: visibleItems
                                .where((item) => item.category == category)
                                .toList(),
                            isLoading: state.isLoading,
                            onTap: cubit.open,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (state.hasMore)
                          Center(
                            child: state.isLoadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: cubit.loadMore,
                                    child: const Text('โหลดแจ้งเตือนเพิ่มเติม'),
                                  ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationSection extends StatelessWidget {
  const _NotificationSection({
    required this.category,
    required this.items,
    required this.isLoading,
    required this.onTap,
  });

  final AppNotificationCategory category;
  final List<AppNotification> items;
  final bool isLoading;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, empty) = switch (category) {
      AppNotificationCategory.rental => (
        'สถานะอุปกรณ์',
        'ติดตามความคืบหน้าคำสั่งเช่าและสถานะอุปกรณ์',
        'ยังไม่มีการแจ้งเตือนสถานะการเช่า',
      ),
      AppNotificationCategory.chat => (
        'ข้อความแชต',
        'ข้อความล่าสุดและจำนวนที่ยังไม่อ่านในแต่ละห้อง',
        'ยังไม่มีการแจ้งเตือนข้อความแชต',
      ),
      AppNotificationCategory.app => (
        'อัปเดตและข้อความระบบ',
        'ข้อมูลบัญชี ความปลอดภัย และความคืบหน้าเรื่องร้องเรียน',
        'ยังไม่มีการแจ้งเตือนระบบ',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text('${items.length}'),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        if (isLoading)
          Semantics(
            label: 'กำลังโหลดการแจ้งเตือน',
            child: SkeletonShimmer(child: _Notice(title: empty)),
          )
        else if (items.isEmpty)
          _Notice(title: empty)
        else
          for (final item in items)
            _NotificationCard(item: item, onTap: () => onTap(item)),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('notification-${item.id}'),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x030F172A),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Icon(
                  switch (item.category) {
                    AppNotificationCategory.chat =>
                      Icons.chat_bubble_outline_rounded,
                    AppNotificationCategory.rental =>
                      Icons.inventory_2_outlined,
                    AppNotificationCategory.app => Icons.notifications_outlined,
                  },
                  size: 18,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _relativeTime(item.updatedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        if (!item.isRead)
                          Semantics(
                            label: 'ยังไม่อ่าน',
                            child: Container(
                              key: ValueKey('notification-unread-${item.id}'),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: item.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: switch (item.type) {
                        'complaint_listing_warning' ||
                        'complaint_listing_removed' => null,
                        _ => 3,
                      },
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                    if (item.category == AppNotificationCategory.chat &&
                        item.unreadCount > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${item.unreadCount} ข้อความที่ยังไม่อ่าน',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return DateFormat('d/M/yyyy HH:mm').format(time.toLocal());
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        const Icon(Icons.inbox_outlined, size: 22, color: Color(0xFF94A3B8)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ),
  );
}
