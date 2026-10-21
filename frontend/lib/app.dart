import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/navigation/app_routes.dart';
import 'core/navigation/item_deep_link.dart';
import 'core/network/supabase_client.dart';
import 'core/services/app_orientation_service.dart';
import 'core/services/chat_notification_service.dart';
import 'core/services/app_notification_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/recommendation_location_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/notification/presentation/widgets/global_app_notification_listener.dart';
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
  StreamSubscription<dynamic>? _authStateSubscription;

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
    if (SupabaseConfig.isInitialized) {
      _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange
          .listen((data) {
            if (data.event.name == 'signedIn' ||
                data.event.name == 'tokenRefreshed') {
              unawaited(
                RecommendationLocationService.instance
                    .syncPendingForSignedInUser(),
              );
            }
          });
    }
    unawaited(_handleInitialDeepLink());

    ChatNotificationService.instance.onNotificationTapped = (conversationId) =>
        unawaited(_openConversation(conversationId));
    AppNotificationService.instance.onOpen = _openNotification;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppOrientationService.setupOrientation();
      // ผูก callback หลัง navigator พร้อม เพื่อไม่ทำการแตะ Push ตอน cold start หาย
      FcmService.instance.onNotificationOpened = _openPush;
    });
  }

  Future<void> _openConversation(String conversationId) async {
    if (!mounted || conversationId.isEmpty) return;
    try {
      final conversation = await ChatRemoteDataSource().getConversationById(
        conversationId,
      );
      if (mounted && conversation != null) {
        unawaited(AppRoutes.openChatDetail(null, conversation: conversation));
        return;
      }
    } catch (_) {}
    if (mounted) _router.go(AppRoutes.notification);
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!mounted) return;
    if (notification.conversationId != null) {
      await _openConversation(notification.conversationId!);
      return;
    }
    _navigateNotification(notification.data, notification.bookingId);
  }

  Future<void> _openPush(Map<String, dynamic> data) async {
    if (!mounted) return;
    final service = AppNotificationService.instance;
    await service.refresh();
    if (!mounted) return;
    final id = data['notification_id']?.toString();
    for (final item in service.inbox.value.items) {
      if (item.id == id) {
        await service.open(item);
        return;
      }
    }
    final conversationId = data['conversation_id']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      await _openConversation(conversationId);
    } else {
      _navigateNotification(data, data['booking_id']?.toString());
    }
  }

  void _navigateNotification(Map<String, dynamic> data, String? bookingId) {
    if (!mounted) return;
    final destination = data['destination']?.toString();
    if (bookingId != null) {
      _router.push(
        '${AppRoutes.rentalStatus}?booking_id=${Uri.encodeComponent(bookingId)}',
      );
    } else if (destination == AppRoutes.identity ||
        destination == AppRoutes.myItems) {
      _router.push(destination!);
    } else {
      _router.go(AppRoutes.notification);
    }
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
      final userId = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentUser?.id
          : null;
      if (userId != null) unawaited(FcmService.instance.syncUserToken(userId));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_authStateSubscription?.cancel());
    FcmService.instance.onNotificationOpened = null;
    AppNotificationService.instance.onOpen = null;
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
          return GlobalAppNotificationListener(
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
