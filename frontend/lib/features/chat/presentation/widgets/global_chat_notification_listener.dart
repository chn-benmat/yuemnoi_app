import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/active_conversation_tracker.dart';
import '../../../../core/services/chat_notification_service.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import 'in_app_notification_banner.dart';

class GlobalChatNotificationListener extends StatefulWidget {
  const GlobalChatNotificationListener({
    super.key,
    required this.child,
    this.dataSource,
    this.notificationService,
  });

  final Widget child;
  final ChatRemoteDataSource? dataSource;
  final ChatNotificationService? notificationService;

  @override
  State<GlobalChatNotificationListener> createState() =>
      _GlobalChatNotificationListenerState();
}

class _GlobalChatNotificationListenerState
    extends State<GlobalChatNotificationListener>
    with WidgetsBindingObserver {
  late final ChatRemoteDataSource _dataSource;
  late final ChatNotificationService _notificationService;
  StreamSubscription<List<IncomingChatMessageData>>? _incomingMsgSub;

  final Set<String> _notifiedMessageIds = <String>{};
  IncomingChatMessageData? _activeBanner;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataSource = widget.dataSource ?? ChatRemoteDataSource();
    _notificationService =
        widget.notificationService ?? ChatNotificationService.instance;

    _notificationService.initialize();
    _startListening();

    try {
      if (SupabaseConfig.isInitialized) {
        SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
          if (mounted && data.session?.user.id != null) {
            _incomingMsgSub?.cancel();
            _startListening();
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  void _startListening() {
    try {
      _incomingMsgSub = _dataSource.streamIncomingMessages().listen((messages) {
        if (!mounted) return;

        for (final msg in messages) {
          if (_notifiedMessageIds.contains(msg.id)) continue;
          _notifiedMessageIds.add(msg.id);

          // ถ้ากำลังเปิดแชทกับคนนี้อยู่แล้ว ไม่ต้องแสดงการแจ้งเตือน
          if (ActiveConversationTracker.instance.isConversationActive(
            msg.conversationId,
          )) {
            continue;
          }

          if (_lifecycleState == AppLifecycleState.resumed) {
            // อยู่ในแอป แต่ไม่ได้อยู่ในแชทนั้น: เล่นเสียง + แสดง Banner ด้านบน 3 วินาที
            _notificationService.playMessageSound();
            setState(() {
              _activeBanner = msg;
            });
          }
          // หมายเหตุ: เมื่อแอปอยู่นอกหน้าจอ/พื้นหลัง (Background) ระบบ FCM Push Notification
          // จะเป็นผู้รับผิดชอบการยิงแจ้งเตือนลง System Tray โดยตรง เพื่อป้องกันการเกิดการแจ้งเตือนซ้ำ 2 อัน
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingMsgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_activeBanner != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: InAppNotificationBanner(
              key: ValueKey(_activeBanner!.id),
              conversation: _activeBanner!.conversation,
              message: _activeBanner!.message,
              onTap: () {
                final conv = _activeBanner!.conversation;
                setState(() {
                  _activeBanner = null;
                });
                AppRoutes.openChatDetail(context, conversation: conv);
              },
              onDismiss: () {
                if (mounted) {
                  setState(() {
                    _activeBanner = null;
                  });
                }
              },
            ),
          ),
      ],
    );
  }
}
