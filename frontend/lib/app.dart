import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/navigation/app_routes.dart';
import 'core/navigation/item_deep_link.dart';
import 'core/services/app_orientation_service.dart';
import 'core/services/chat_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/chat/domain/entities/chat_conversation.dart';
import 'features/chat/presentation/widgets/global_chat_notification_listener.dart';
import 'features/wallet/presentation/bloc/wallet_cubit.dart';

class YuemnoiApp extends StatefulWidget {
  const YuemnoiApp({super.key, this.initialRoute = AppRoutes.home});

  final String initialRoute;

  @override
  State<YuemnoiApp> createState() => _YuemnoiAppState();
}

class _YuemnoiAppState extends State<YuemnoiApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = AppRoutes.createRouter(initialLocation: widget.initialRoute);
    _deepLinkSubscription = AppLinks().uriLinkStream.listen(
      _handleDeepLink,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Deep link warning: $error');
      },
    );
    unawaited(_handleInitialDeepLink());

    ChatNotificationService.instance.onNotificationTapped =
        (conversationId) async {
          if (conversationId.isNotEmpty) {
            try {
              final fullConv = await ChatRemoteDataSource().getConversationById(
                conversationId,
              );
              if (fullConv != null) {
                AppRoutes.openChatDetail(null, conversation: fullConv);
                return;
              }
            } catch (_) {}

            final conv = ChatConversation(
              id: conversationId,
              otherUserId: '',
              name: 'ห้องแชท',
              role: ChatParticipantRole.owner,
              avatarAsset: 'assets/images/user.png',
              preview: '',
              timeLabel: '',
            );
            AppRoutes.openChatDetail(null, conversation: conv);
          }
        };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppOrientationService.setupOrientation();
    });
  }

  Future<void> _handleInitialDeepLink() async {
    try {
      final uri = await AppLinks().getInitialLink();
      if (uri == null || !mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleDeepLink(uri);
      });
    } catch (error) {
      debugPrint('Initial deep link warning: $error');
    }
  }

  void _handleDeepLink(Uri uri) {
    final itemId = ItemDeepLink.parseItemId(uri);
    if (itemId == null) return;

    _router.push('/items/$itemId');
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    AppOrientationService.setupOrientation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AppOrientationService.setupOrientation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_deepLinkSubscription?.cancel());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            authRepository: AuthRepositoryImpl(AuthRemoteDataSource()),
          ),
        ),
        BlocProvider<WalletCubit>(create: (context) => WalletCubit()),
      ],
      child: MaterialApp.router(
        title: 'Yuemnoi App',
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        builder: (context, child) {
          return GlobalChatNotificationListener(
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
