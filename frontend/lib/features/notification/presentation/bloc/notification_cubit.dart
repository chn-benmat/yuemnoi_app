import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/app_notification_service.dart';

class NotificationCubit extends Cubit<NotificationInboxState> {
  NotificationCubit(this.service) : super(service.inbox.value) {
    service.inbox.addListener(_onInboxChanged);
  }

  final AppNotificationService service;

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
    return super.close();
  }
}
