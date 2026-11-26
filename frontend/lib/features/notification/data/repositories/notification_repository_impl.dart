import '../../../../core/network/api_client.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_remote_data_source.dart';
import '../models/app_notification_model.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl({
    NotificationRemoteDataSource? dataSource,
    this.category,
  }) : _dataSource = dataSource ?? NotificationRemoteDataSource();

  final NotificationRemoteDataSource _dataSource;
  final AppNotificationCategory? category;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiClientException {
      throw const NotificationFailure(
        'เชื่อมต่อการแจ้งเตือนไม่ได้ กรุณาลองใหม่',
      );
    }
  }

  @override
  Future<NotificationInboxPage> getInbox({
    int limit = 50,
    int offset = 0,
  }) => _request(() async {
    final result = await _dataSource.fetch(
      limit: limit,
      offset: offset,
      category: category,
    );
    final items = result['items'];
    final serverTime = DateTime.tryParse('${result['server_time']}');
    if (items is! List || serverTime == null) {
      throw const NotificationFailure('รูปแบบข้อมูลแจ้งเตือนไม่ถูกต้อง');
    }
    return NotificationInboxPage(
      items: List<AppNotification>.unmodifiable(
        items.map((item) {
          if (item is! Map) {
            throw const NotificationFailure('รูปแบบข้อมูลแจ้งเตือนไม่ถูกต้อง');
          }
          return AppNotificationModel.fromJson(Map<String, dynamic>.from(item));
        }),
      ),
      unreadCount: int.tryParse('${result['unread_count']}') ?? 0,
      serverTime: serverTime,
    );
  });

  @override
  Future<void> markRead(String id, {DateTime? readThrough}) => _request(
    () => _dataSource.post(
      '/api/notifications/${Uri.encodeComponent(id)}/read',
      data: {
        if (readThrough != null)
          'read_through': readThrough.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<void> markAllRead({DateTime? readThrough}) => _request(
    () => _dataSource.post(
      '/api/notifications/read-all',
      data: {
        if (readThrough != null)
          'read_through': readThrough.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<void> markConversationRead(String conversationId) => _request(
    () => _dataSource.post(
      '/api/notifications/read-conversation',
      data: {'conversation_id': conversationId},
    ),
  );

  @override
  void close() => _dataSource.close();
}
