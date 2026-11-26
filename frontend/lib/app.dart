import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import 'core/navigation/app_routes.dart';
import 'core/navigation/item_deep_link.dart';
import 'core/network/auth_session.dart';
import 'core/network/supabase_client.dart';
import 'core/services/app_notification_service.dart';
import 'core/services/app_orientation_service.dart';
import 'core/services/app_permission_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/recommendation_location_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/notification/presentation/widgets/global_app_notification_listener.dart';
import 'features/wallet/presentation/bloc/wallet_cubit.dart';

class YuemnoiApp extends StatefulWidget {
  const YuemnoiApp({
    super.key,
    this.initialRoute = AppRoutes.home,
    this.oauthRestoreSession,
  });

  final String initialRoute;
  final Session? oauthRestoreSession;

  @override
  State<YuemnoiApp> createState() => _YuemnoiAppState();
}

class _YuemnoiAppState extends State<YuemnoiApp> with WidgetsBindingObserver {
  static const _notificationPermissionRequested =
      'startup_notification_permission_requested_v1';
  static const _locationPermissionRequested =
      'startup_location_permission_requested_v1';

  late final GoRouter _router;
  StreamSubscription<Uri>? _deepLinkSubscription;
  bool _startupPermissionsComplete = false;
  int _notificationNavigationId = 0;

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

    AppNotificationService.instance.onOpen = _openNotification;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppOrientationService.setupOrientation();
      // ผูก callback หลัง navigator พร้อม เพื่อไม่ทำการแตะ Push ตอน cold start หาย
      FcmService.instance.onNotificationOpened = _openPush;
      unawaited(_requestFirstLaunchPermissions());
    });
  }

  Future<void> _requestFirstLaunchPermissions() async {
    if (!RecommendationLocationService.isSupported) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      if (prefs.getBool(_notificationPermissionRequested) != true) {
        try {
          await AppPermissionService.requestNotificationPermission();
          await prefs.setBool(_notificationPermissionRequested, true);
        } catch (_) {
          debugPrint('ขอสิทธิ์แจ้งเตือนไม่สำเร็จ');
        }
      }
      if (!mounted) return;
      final requestLocation =
          prefs.getBool(_locationPermissionRequested) != true;
      await RecommendationLocationService.instance.refresh(
        requestPermission: requestLocation,
      );
      if (requestLocation) {
        await prefs.setBool(_locationPermissionRequested, true);
      }
    } catch (_) {
      debugPrint('เตรียมสิทธิ์เมื่อเปิดแอปไม่สำเร็จ');
    } finally {
      _startupPermissionsComplete = true;
    }
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
    if (mounted) _openHomeTab(1);
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (!mounted) return;
    if (notification.category == AppNotificationCategory.chat) {
      final conversationId = notification.conversationId;
      if (conversationId != null) await _openConversation(conversationId);
      return;
    }
    _navigateNotification({
      ...notification.data,
      'category': notification.category.name,
      if (notification.bookingId != null) 'booking_id': notification.bookingId,
    }, openHistoryIfUnknown: false);
  }

  Future<void> _openPush(Map<String, dynamic> data) async {
    if (!mounted) return;
    final id = data['notification_id']?.toString();
    final updatedAt = DateTime.tryParse('${data['updated_at']}');
    if (id != null && id.isNotEmpty && updatedAt != null) {
      unawaited(
        AppNotificationService.instance.markPushRead(
          id,
          readThrough: updatedAt,
        ),
      );
    }
    final conversationId = data['conversation_id']?.toString();
    final isChat = data['category'] == 'chat' || data['type'] == 'chat_message';
    if (isChat) {
      if (conversationId != null && conversationId.isNotEmpty) {
        await _openConversation(conversationId);
      } else {
        _openHomeTab(1);
      }
      return;
    }
    _navigateNotification(data);
  }

  void _navigateNotification(
    Map<String, dynamic> data, {
    bool openHistoryIfUnknown = true,
  }) {
    final destination = data['destination']?.toString();
    final bookingId = int.tryParse('${data['booking_id']}');
    if (bookingId != null && bookingId > 0) {
      _router.push('${AppRoutes.rentalStatus}?booking_id=$bookingId');
    } else if (data['category'] == 'rental') {
      _router.push(AppRoutes.rentalStatus);
    } else if (destination == AppRoutes.identity ||
        destination == AppRoutes.myItems) {
      _router.push(destination!);
    } else if (openHistoryIfUnknown) {
      _openHomeTab(2);
    }
  }

  void _openHomeTab(int index) {
    _router.go(
      AppRoutes.home,
      extra: {
        'initialIndex': index,
        'navigationId': ++_notificationNavigationId,
      },
    );
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
    final oauthRedirect = Uri.parse(SupabaseConfig.oauthRedirectUrl);
    if (uri.scheme == oauthRedirect.scheme && uri.host == oauthRedirect.host) {
      if (!AuthSession.isAuthenticated &&
          _router.state.matchedLocation != AppRoutes.login) {
        _router.go(AppRoutes.login);
      }
      return;
    }
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
      if (_startupPermissionsComplete) {
        unawaited(RecommendationLocationService.instance.refresh());
      }
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
          create: (_) {
            final bloc = AuthBloc(
              authRepository: AuthRepositoryImpl(AuthRemoteDataSource()),
            );
            final session = widget.oauthRestoreSession;
            if (session != null) bloc.add(AuthAuthStateChanged(session));
            return bloc;
          },
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
