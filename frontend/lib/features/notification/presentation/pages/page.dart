import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/navigation/notification_navigation.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/skeleton_layout_cache.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_page_header.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../data/notification_remote_data_source.dart';
import '../../domain/app_notification.dart';
import '../bloc/notification_cubit.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key, this.dataSource});

  final NotificationRemoteDataSource? dataSource;

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with WidgetsBindingObserver {
  static const _inboxPadding = EdgeInsets.fromLTRB(16, 8, 16, 120);

  late final _inbox = NotificationCubit(source: widget.dataSource);
  StreamSubscription<void>? _pushUpdates;
  StreamSubscription<Object?>? _authChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushUpdates = FcmService.instance.updates.listen(
      (_) => unawaited(_inbox.load()),
    );
    if (SupabaseConfig.isInitialized) {
      _authChanges = SupabaseConfig.client.auth.onAuthStateChange.listen((_) {
        if (mounted && AuthSession.userId != _inbox.state.userId)
          unawaited(_inbox.load());
      }, onError: (Object _) {});
    }
    unawaited(_inbox.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_inbox.load());
  }

  Future<void> _open(AppNotification item) async {
    final userId = AuthSession.userId;
    if (userId == null || userId != _inbox.state.userId) return;
    final router = GoRouter.of(context);
    await _inbox.markRead(item);
    if (!mounted || AuthSession.userId != userId) return;
    await openAppNotification(router, item);
    if (mounted) await _inbox.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_pushUpdates?.cancel());
    unawaited(_authChanges?.cancel());
    unawaited(_inbox.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _NotifPalette.bg,
    body: BlocConsumer<NotificationCubit, NotificationInboxState>(
      bloc: _inbox,
      // จำว่าแสดงกี่รายการและอ่านแล้วหรือยัง ให้ skeleton รอบหน้าออกมาตรงกัน
      listenWhen: (previous, next) =>
          !next.loading &&
          !next.failed &&
          next.userId != null &&
          next.userId == AuthSession.userId,
      listener: (context, state) => SkeletonLayoutCache.instance.write(
        _skeletonKey(state.userId!),
        [for (final item in state.items) item.isRead ? 'r' : 'u'],
      ),
      builder: (context, state) {
        final signedIn =
            AuthSession.userId != null && AuthSession.userId == state.userId;
        final unread = signedIn
            ? state.items.where((item) => !item.isRead).length
            : 0;
        return Column(
          children: [
            _Header(unread: unread),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: false,
                child: _buildInbox(context, state),
              ),
            ),
          ],
        );
      },
    ),
  );

  static String _skeletonKey(String userId) => 'notifications.$userId';

  Widget _buildInbox(BuildContext context, NotificationInboxState state) {
    if (AuthSession.userId == null || AuthSession.userId != state.userId) {
      return _StatusView(
        icon: Icons.notifications_active_rounded,
        title: 'อย่าพลาดทุกความเคลื่อนไหว',
        message: 'แชทใหม่ คำขอยืม และเวลาคืนของ จะเด้งมาที่นี่',
        action: 'เข้าสู่ระบบเพื่อดูการแจ้งเตือน',
        onAction: () async {
          await AppRoutes.pushLogin(context);
          if (mounted) await _inbox.load();
        },
      );
    }
    if (state.items.isEmpty && state.loading) {
      // ใช้จำนวนและสถานะอ่านของรอบก่อน ถ้ายังไม่เคยโหลดจึงใช้ค่าเริ่มต้น
      final layout =
          SkeletonLayoutCache.instance.read(_skeletonKey(state.userId!)) ??
          List.filled(6, 'r');
      return ListView.builder(
        key: const ValueKey('notification-loading-skeleton'),
        physics: const NeverScrollableScrollPhysics(),
        padding: _inboxPadding,
        itemCount: layout.length,
        itemBuilder: (context, index) =>
            _NotificationSkeletonTile(unread: layout[index] == 'u'),
      );
    }
    if (state.items.isEmpty && state.failed) {
      return _StatusView(
        icon: Icons.wifi_off_rounded,
        title: 'อุ๊ย โหลดไม่ขึ้น',
        message: 'เช็กอินเทอร์เน็ตแล้วลองใหม่อีกครั้งนะ',
        action: 'โหลดแจ้งเตือนไม่สำเร็จ ลองอีกครั้ง',
        onAction: _inbox.load,
      );
    }

    final items = state.items;
    final children = <Widget>[];
    String? lastGroup;
    var index = 0;
    for (final item in items) {
      final group = _groupLabel(item.updatedAt);
      if (group != lastGroup) {
        children.add(_SectionLabel(group));
        lastGroup = group;
      }
      children.add(
        _NotificationCard(
          key: ValueKey(item.id),
          item: item,
          index: index++,
          onTap: () => unawaited(_open(item)),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryColor,
      onRefresh: _inbox.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _inboxPadding,
        children: [
          if (items.isEmpty)
            const _EmptyView(
              icon: Icons.notifications_none_rounded,
              title: 'ยังไม่มีการแจ้งเตือน',
              message: 'ลองยืมของหรือปล่อยเช่าดู แล้วอัปเดตจะมาที่นี่',
            ),
          ...children,
          if (state.loading)
            const _NotificationSkeletonTile()
          else if (state.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    textStyle: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => unawaited(_inbox.load(more: true)),
                  icon: Icon(
                    state.failed
                        ? Icons.refresh_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(state.failed ? 'ลองอีกครั้ง' : 'ดูเพิ่มเติม'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// จัดกลุ่มตามวันปฏิทินของเครื่อง เพื่อให้หัวข้อ "วันนี้/เมื่อวาน" ตรงกับที่ผู้ใช้เห็น
String _groupLabel(DateTime? time) {
  if (time == null) return 'ก่อนหน้านี้';
  final now = DateTime.now();
  final local = time.toLocal();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) return 'วันนี้';
  if (days == 1) return 'เมื่อวาน';
  if (days < 7) return 'สัปดาห์นี้';
  return 'ก่อนหน้านี้';
}

String _relativeTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'เมื่อกี้';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาที';
  if (diff.inHours < 24) return '${diff.inHours} ชม.';
  if (diff.inDays < 7) return '${diff.inDays} วัน';
  return DateFormat('d/M HH:mm').format(local);
}

class _NotifPalette {
  static const bg = Color(0xFFF6F4FB);
  static const ink = Color(0xFF16112A);
  static const muted = Color(0xFF6E6A80);
}

class _TypeStyle {
  const _TypeStyle(this.icon, this.from, this.to, this.tag);
  final IconData icon;
  final Color from;
  final Color to;
  final String tag;

  static _TypeStyle of(String type) => switch (type) {
    'chat_message' => const _TypeStyle(
      Icons.chat_bubble_rounded,
      Color(0xFF3B82F6),
      Color(0xFF22D3EE),
      'แชท',
    ),
    'rental_request_received' => const _TypeStyle(
      Icons.handshake_rounded,
      Color(0xFF7400C9),
      Color(0xFFC185FF),
      'คำขอยืม',
    ),
    'identity_approved' => const _TypeStyle(
      Icons.verified_rounded,
      Color(0xFF10B981),
      Color(0xFF84CC16),
      'ยืนยันตัวตน',
    ),
    'rental_review_pending' => const _TypeStyle(
      Icons.star_rounded,
      Color(0xFFF59E0B),
      Color(0xFFFBBF24),
      'รีวิว',
    ),
    'rental_due_1h' || 'rental_due_30m' => const _TypeStyle(
      Icons.alarm_rounded,
      Color(0xFFF43F5E),
      Color(0xFFFB923C),
      'ใกล้ถึงเวลาคืน',
    ),
    'rental_queue_ready' => const _TypeStyle(
      Icons.schedule_rounded,
      Color(0xFFEC4899),
      Color(0xFFF472B6),
      'ถึงคิวแล้ว',
    ),
    _ => const _TypeStyle(
      Icons.inventory_2_rounded,
      Color(0xFF8B5CF6),
      Color(0xFFA78BFA),
      'อัปเดต',
    ),
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.unread});

  final int unread;

  @override
  // ใช้ AppPageHeader ร่วมกับหน้าอื่น ให้สีหัวและ status bar ตรงกันทั้งแอป
  Widget build(BuildContext context) => AppPageTitleHeader(
    title: 'การแจ้งเตือน',
    trailing: AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: unread == 0
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(unread),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'ใหม่ ${unread > 99 ? '99+' : unread}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: _NotifPalette.muted,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
  });

  final AppNotification item;
  final int index;
  final VoidCallback onTap;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final style = _TypeStyle.of(item.type);
    final unread = !item.isRead;
    // ไล่จังหวะการ์ดให้ค่อยๆ โผล่ แต่จำกัดเพดานไว้ไม่ให้รายการท้ายๆ รอนาน
    final duration = 260 + 45 * (widget.index > 8 ? 8 : widget.index);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: unread
                        ? style.from.withValues(alpha: 0.28)
                        : const Color(0xFFEDEAF5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: unread
                          ? style.from.withValues(alpha: 0.12)
                          : const Color(0x0A16112A),
                      blurRadius: unread ? 18 : 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [style.from, style.to],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: style.from.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(style.icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: style.from.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    style.tag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: style.from,
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _relativeTime(item.updatedAt),
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: unread
                                      ? AppColors.primaryColor
                                      : _NotifPalette.muted,
                                ),
                              ),
                              if (unread) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF43F5E),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: _NotifPalette.ink,
                            ),
                          ),
                          if (item.body.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                height: 1.4,
                                color: _NotifPalette.muted,
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
        ),
      ),
    );
  }
}

class _GlowIcon extends StatelessWidget {
  const _GlowIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 96,
    height: 96,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.gradient1, AppColors.gradient2],
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryColor.withValues(alpha: 0.3),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Icon(icon, color: Colors.white, size: 44),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 72),
    child: Column(
      children: [
        _GlowIcon(icon),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _NotifPalette.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            color: _NotifPalette.muted,
          ),
        ),
      ],
    ),
  );
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlowIcon(icon),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _NotifPalette.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              height: 1.4,
              color: _NotifPalette.muted,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => unawaited(onAction()),
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

class _NotificationSkeletonTile extends StatelessWidget {
  const _NotificationSkeletonTile({this.unread = false});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    // พื้นการ์ดอยู่นอก shimmer เพราะ shimmer ทาสีทับทุกอย่างข้างใน
    // ขอบสีหลักบอกว่ารอบก่อนรายการนี้ยังไม่อ่าน ให้ตรงกับการ์ดจริง
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: unread
                ? AppColors.primaryColor.withValues(alpha: 0.2)
                : const Color(0xFFEDEAF5),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: SkeletonShimmer(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 46, height: 46, borderRadius: 15),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SkeletonBox(width: 56, height: 14, borderRadius: 99),
                          Spacer(),
                          SkeletonBox(width: 40, height: 12, borderRadius: 4),
                        ],
                      ),
                      SizedBox(height: 10),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 0.8,
                        child: SkeletonBox(height: 15, borderRadius: 6),
                      ),
                      SizedBox(height: 8),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 0.55,
                        child: SkeletonBox(height: 12, borderRadius: 5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
