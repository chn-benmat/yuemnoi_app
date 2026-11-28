import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/widgets/custom_bottom_navbar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../chat/domain/usecases/get_conversations_usecase.dart';
import '../../../chat/presentation/bloc/chat_list_bloc.dart';
import '../../../chat/presentation/bloc/chat_list_event.dart';
import '../../../chat/presentation/bloc/chat_list_state.dart';
import '../../../chat/presentation/pages/chat.dart';
import '../../../notification/presentation/bloc/notification_badge_cubit.dart';
import '../../../notification/presentation/pages/page.dart';
import '../../../profile/presentation/pages/profile/profile.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import '../services/skeleton_layout_warmup.dart';
import 'home_feed_view.dart';

class HomeScreen extends StatelessWidget {
  final int initialIndex;
  final String? initialMessage;
  const HomeScreen({super.key, this.initialIndex = 0, this.initialMessage});

  @override
  Widget build(BuildContext context) {
    final chatRepository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<HomeBloc>(
          create: (context) {
            final homeRepository = HomeRepositoryImpl();
            return HomeBloc(
              homeRepository: homeRepository,
              getHomeFeed: GetHomeFeedUseCase(homeRepository),
              feedChanges: homeRepository.watchFeedChanges(),
            )..add(const LoadHomeFeedStarted());
          },
        ),
        BlocProvider<NotificationBadgeCubit>(
          create: (context) => NotificationBadgeCubit(),
        ),
        BlocProvider<ChatListBloc>(
          create: (context) {
            final bloc = ChatListBloc(
              getConversations: GetConversationsUseCase(chatRepository),
            );
            if (AuthSession.isAuthenticated) {
              bloc.add(const LoadChatListStarted());
              unawaited(SkeletonLayoutWarmup.instance.warmScreens());
            }
            // รายการแชทโหลดเสร็จหลังเข้าสู่ระบบ (รวมกรณีล็อกอินทีหลัง) เตรียม skeleton
            // ของหน้าต่าง ๆ ไว้ก่อนผู้ใช้เปิด จะได้ตรงตั้งแต่ครั้งแรก ไม่ต้องรอเปิดรอบสอง
            // subscription จบเองเมื่อ bloc ปิด stream
            bloc.stream
                .where((state) => state.status == ChatListStatus.success)
                .listen((state) {
                  unawaited(SkeletonLayoutWarmup.instance.warmScreens());
                  unawaited(
                    SkeletonLayoutWarmup.instance.warmChats(
                      state.conversations,
                      chatRepository,
                    ),
                  );
                });
            return bloc;
          },
        ),
      ],
      child: _HomeScreenContent(
        key: ValueKey('home_content_$initialIndex'),
        initialIndex: initialIndex,
        initialMessage: initialMessage,
      ),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final int initialIndex;
  final String? initialMessage;
  const _HomeScreenContent({
    super.key,
    this.initialIndex = 0,
    this.initialMessage,
  });

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent>
    with WidgetsBindingObserver {
  static const _notificationTab = 2;
  late int _selectedIndex;
  StreamSubscription<void>? _pushUpdates;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _showInitialMessage(widget.initialMessage);
    WidgetsBinding.instance.addObserver(this);
    _pushUpdates = FcmService.instance.updates.listen(
      (_) => _refreshNotificationBadge(),
    );
    _refreshNotificationBadge();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshNotificationBadge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_pushUpdates?.cancel());
    super.dispose();
  }

  // จุดแดงหายเฉพาะเมื่อผู้ใช้เข้าแท็บแจ้งเตือน ระหว่างอยู่ในแท็บนี้ถือว่าเห็นแจ้งเตือนใหม่แล้ว
  void _refreshNotificationBadge() {
    if (!mounted) return;
    final badge = context.read<NotificationBadgeCubit>();
    unawaited(
      _selectedIndex == _notificationTab ? badge.markSeen() : badge.check(),
    );
  }

  void _selectTab(int index) {
    final leavingNotifications =
        _selectedIndex == _notificationTab && index != _notificationTab;
    setState(() => _selectedIndex = index);
    // ออกจากแท็บก็บันทึกอีกครั้ง เผื่อแจ้งเตือนที่อ่านระหว่างนั้นถูกอัปเดตเวลา
    if (index == _notificationTab || leavingNotifications) {
      unawaited(context.read<NotificationBadgeCubit>().markSeen());
    }
  }

  void _showInitialMessage(String? message) {
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void didUpdateWidget(covariant _HomeScreenContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMessage != widget.initialMessage) {
      _showInitialMessage(widget.initialMessage);
    }
    if (oldWidget.initialIndex != widget.initialIndex ||
        (widget.initialMessage != null &&
            oldWidget.initialMessage != widget.initialMessage)) {
      _selectTab(widget.initialIndex);
    }
  }

  List<Widget> get _pages => [
    const HomeFeedView(),
    const ChatScreen(),
    if (_selectedIndex == 2)
      const NotificationPage()
    else
      const SizedBox.shrink(),
    ProfileScreen(isActive: _selectedIndex == 3),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, authState) {
        if (authState is LoginSuccess || authState is GoogleLoginSuccess) {
          context.read<ChatListBloc>().add(const LoadChatListStarted());
          _refreshNotificationBadge();
          if (mounted) setState(() {});
        }
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _selectedIndex, children: _pages),
        floatingActionButton: _selectedIndex == 0
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: FloatingActionButton(
                      heroTag: 'chatbot-fab',
                      tooltip: 'แชตบอต',
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      onPressed: () => AppRoutes.openChatbot(context),
                      child: const Icon(Icons.smart_toy_rounded, size: 34),
                    ),
                  ),
                ],
              )
            : null,
        bottomNavigationBar: BlocBuilder<ChatListBloc, ChatListState>(
          builder: (context, chatState) {
            final hasUnread = chatState.conversations.any(
              (c) => c.hasUnreadMessage,
            );

            final hasNewNotification = context
                .watch<NotificationBadgeCubit>()
                .state;

            return CustomBottomNavbar(
              selectedIndex: _selectedIndex,
              hasUnreadChat: hasUnread,
              hasNewNotification:
                  hasNewNotification && _selectedIndex != _notificationTab,
              onTabChange: _selectTab,
            );
          },
        ),
      ),
    );
  }
}
