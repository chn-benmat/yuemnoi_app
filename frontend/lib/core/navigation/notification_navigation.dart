import 'package:go_router/go_router.dart';

import '../../features/chat/data/datasources/chat_remote_data_source.dart';
import '../../features/notification/domain/app_notification.dart';
import '../network/auth_session.dart';
import 'app_routes.dart';

Future<void> openAppNotification(
  GoRouter router,
  AppNotification notification,
) async {
  final userId = AuthSession.userId;
  if (userId == null) return;
  final roomId = notification.conversationId;
  if (roomId != null && roomId.isNotEmpty) {
    try {
      final room = await ChatRemoteDataSource().getConversationById(roomId);
      if (AuthSession.userId != userId) return;
      if (room != null) {
        await router.push<void>(AppRoutes.chatDetail, extra: room);
        return;
      }
    } catch (_) {}
    if (AuthSession.userId != userId) return;
  }

  final path = switch (notification.type) {
    'item_approved' => AppRoutes.myItems,
    'identity_approved' => AppRoutes.identityAccount,
    'rental_due_1h' || 'rental_due_30m' => AppRoutes.rentalStatus,
    'rental_review_pending' => AppRoutes.rentalHistory,
    'rental_request_received' => '${AppRoutes.rentalStatus}?role=lender',
    _ => null,
  };
  if (path != null) {
    await router.push<void>(path);
  } else {
    router.go(AppRoutes.home, extra: {'initialIndex': 1});
  }
}
