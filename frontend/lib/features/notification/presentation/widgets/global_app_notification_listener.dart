import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/services/active_conversation_tracker.dart';
import '../../../../core/services/app_notification_service.dart';
import '../../../../core/services/chat_notification_service.dart';

class GlobalAppNotificationListener extends StatefulWidget {
  const GlobalAppNotificationListener({
    super.key,
    required this.child,
    this.service,
    this.playSound,
    this.duration = const Duration(seconds: 4),
  });

  final Widget child;
  final AppNotificationService? service;
  final Future<void> Function()? playSound;
  final Duration duration;

  @override
  State<GlobalAppNotificationListener> createState() =>
      _GlobalAppNotificationListenerState();
}

class _GlobalAppNotificationListenerState
    extends State<GlobalAppNotificationListener>
    with WidgetsBindingObserver {
  late final AppNotificationService _service;
  StreamSubscription<AppNotification>? _subscription;
  Timer? _dismissTimer;
  AppNotification? _active;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppNotificationService.instance;
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _service.setForeground(_foreground);
    _service.inbox.addListener(_onInboxChanged);
    _subscription = _service.foregroundEvents.listen(_show);
  }

  void _onInboxChanged() {
    final current = _active;
    if (current == null || !mounted) return;
    final state = _service.inbox.value;
    final item = state.items.where((item) => item.id == current.id);
    if (!state.isAuthenticated || item.isEmpty || item.first.isRead) _dismiss();
  }

  void _show(AppNotification item) {
    if (!mounted || !_foreground) return;
    final current = _service.inbox.value;
    if (!current.isAuthenticated ||
        !current.items.any(
          (row) => row.versionKey == item.versionKey && !row.isRead,
        )) {
      return;
    }
    if (item.category == AppNotificationCategory.chat &&
        item.conversationId != null &&
        ActiveConversationTracker.instance.isConversationActive(
          item.conversationId!,
        )) {
      unawaited(_service.markConversationRead(item.conversationId!));
      return;
    }
    unawaited(
      (widget.playSound ?? ChatNotificationService.instance.playMessageSound)(),
    );
    _dismissTimer?.cancel();
    setState(() => _active = item);
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (mounted && _active != null) setState(() => _active = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _service.setForeground(_foreground);
    if (!_foreground) _dismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    unawaited(_subscription?.cancel());
    _service.inbox.removeListener(_onInboxChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_active case final item?)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Dismissible(
                key: ValueKey(item.versionKey),
                direction: DismissDirection.up,
                onDismissed: (_) => _dismiss(),
                child: Material(
                  elevation: 8,
                  color: const Color(0xFF1E1B2E),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () {
                      _dismiss();
                      unawaited(_service.open(item));
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            switch (item.category) {
                              AppNotificationCategory.chat =>
                                Icons.chat_bubble_outline_rounded,
                              AppNotificationCategory.rental =>
                                Icons.inventory_2_outlined,
                              AppNotificationCategory.app =>
                                Icons.notifications_outlined,
                            },
                            size: 32,
                            color: AppColors.primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // แบนเนอร์อยู่เหนือ router Overlay จึงใช้ semantics แทน Tooltip
                          Semantics(
                            label: 'ปิดแจ้งเตือน',
                            button: true,
                            child: IconButton(
                              onPressed: _dismiss,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
