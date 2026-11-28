import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/auth_session.dart';
import '../../data/notification_remote_data_source.dart';
import '../../domain/app_notification.dart';

class NotificationInboxState {
  const NotificationInboxState({
    this.userId,
    this.items = const [],
    this.loading = false,
    this.hasMore = false,
    this.failed = false,
  });

  final String? userId;
  final List<AppNotification> items;
  final bool loading;
  final bool hasMore;
  final bool failed;
}

class NotificationCubit extends Cubit<NotificationInboxState> {
  NotificationCubit() : super(const NotificationInboxState());

  static const _pageSize = 40;
  NotificationRemoteDataSource? _source;
  int _request = 0;
  int _offset = 0;

  Future<void> load({bool more = false}) async {
    if (isClosed || (more && (state.loading || !state.hasMore))) return;
    final userId = AuthSession.userId;
    final token = AuthSession.accessToken;
    final request = ++_request;
    if (token == null || userId == null) {
      _offset = 0;
      emit(const NotificationInboxState());
      return;
    }
    final sameUser = userId == state.userId;
    final previous = sameUser ? state.items : const <AppNotification>[];
    final hadMore = sameUser && state.hasMore;
    final offset = sameUser && more ? _offset : 0;
    emit(
      NotificationInboxState(
        userId: userId,
        items: previous,
        hasMore: hadMore,
        loading: true,
      ),
    );
    try {
      final page = await (_source ??= NotificationRemoteDataSource()).fetch(
        token,
        limit: _pageSize,
        offset: offset,
      );
      if (!_isCurrent(request, userId)) return;
      _offset = offset + page.length;
      final ids = <String>{};
      final items = [...(more ? previous : const <AppNotification>[]), ...page];
      emit(
        NotificationInboxState(
          userId: userId,
          items: List.unmodifiable(items.where((item) => ids.add(item.id))),
          hasMore: page.length == _pageSize,
        ),
      );
    } catch (_) {
      if (!_isCurrent(request, userId)) return;
      emit(
        NotificationInboxState(
          userId: userId,
          items: previous,
          hasMore: hadMore,
          failed: true,
        ),
      );
    }
  }

  bool _isCurrent(int request, String userId) =>
      !isClosed && request == _request && AuthSession.userId == userId;

  Future<void> markRead(AppNotification item) async {
    final token = AuthSession.accessToken;
    if (item.isRead || token == null || AuthSession.userId != state.userId)
      return;
    try {
      await _source?.markRead(token, item.id);
    } catch (_) {
      // ยังเปิดรายละเอียดได้เมื่อบันทึกสถานะอ่านไม่สำเร็จ
    }
  }

  @override
  Future<void> close() {
    _source?.close();
    return super.close();
  }
}
