import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/app_notification_service.dart';

class NotificationCubit extends Cubit<NotificationInboxState> {
  NotificationCubit(this.service, {AppNotificationService? sessionSource})
    : _sessionSource = sessionSource,
      super(service.inbox.value) {
    service.inbox.addListener(_onInboxChanged);
    _sessionSource?.inbox.addListener(_syncSession);
    _syncSession();
  }

  final AppNotificationService service;
  final AppNotificationService? _sessionSource;

  void _syncSession() {
    final source = _sessionSource;
    if (source != null) service.setSession(source.sessionUserId);
  }

  void _onInboxChanged() {
    if (!isClosed) emit(service.inbox.value);
  }

  Future<void> refresh() => service.refresh();
  Future<void> loadMore() => service.loadMore();
  Future<void> markAllRead() => service.markAllRead();
  Future<void> open(AppNotification item) => service.open(item);

  @override
  Future<void> close() {
    service.inbox.removeListener(_onInboxChanged);
    _sessionSource?.inbox.removeListener(_syncSession);
    if (_sessionSource != null) service.dispose();
    return super.close();
  }
}
