import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/navigation/notification_navigation.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/app_notification.dart';
import '../bloc/notification_cubit.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with WidgetsBindingObserver {
  final _inbox = NotificationCubit();
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
    backgroundColor: const Color(0xFFF8FAFC),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
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
          ),
          Expanded(
            child: BlocBuilder<NotificationCubit, NotificationInboxState>(
              bloc: _inbox,
              builder: _buildInbox,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildInbox(BuildContext context, NotificationInboxState state) {
    if (AuthSession.userId == null || AuthSession.userId != state.userId) {
      return Center(
        child: TextButton(
          onPressed: () async {
            await AppRoutes.pushLogin(context);
            if (mounted) await _inbox.load();
          },
          child: const Text('เข้าสู่ระบบเพื่อดูการแจ้งเตือน'),
        ),
      );
    }
    if (state.items.isEmpty && state.loading)
      return const Center(child: CircularProgressIndicator());
    if (state.items.isEmpty && state.failed) {
      return Center(
        child: TextButton(
          onPressed: _inbox.load,
          child: const Text('โหลดแจ้งเตือนไม่สำเร็จ ลองอีกครั้ง'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _inbox.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (state.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('ยังไม่มีการแจ้งเตือน')),
            ),
          for (final item in state.items)
            ListTile(
              key: ValueKey(item.id),
              leading: Icon(switch (item.type) {
                'chat_message' => Icons.chat_bubble_outline,
                'identity_approved' => Icons.verified_user_outlined,
                'rental_review_pending' => Icons.star_outline,
                'rental_due_1h' ||
                'rental_due_30m' ||
                'rental_queue_ready' => Icons.schedule,
                _ => Icons.inventory_2_outlined,
              }),
              tileColor: item.isRead
                  ? null
                  : Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.07),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(item.title),
              subtitle: Text(
                item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: item.updatedAt == null
                  ? null
                  : Text(
                      DateFormat('d/M HH:mm').format(item.updatedAt!.toLocal()),
                    ),
              onTap: () => unawaited(_open(item)),
            ),
          if (state.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (state.hasMore)
            TextButton(
              onPressed: () => unawaited(_inbox.load(more: true)),
              child: Text(state.failed ? 'ลองอีกครั้ง' : 'ดูเพิ่มเติม'),
            ),
        ],
      ),
    );
  }
}
