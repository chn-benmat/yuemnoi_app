import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/notification/data/repositories/notification_repository_impl.dart';
import '../../features/notification/domain/entities/app_notification.dart';
import '../../features/notification/domain/repositories/notification_repository.dart';
import '../../features/notification/domain/usecases/notification_usecases.dart';
import 'active_conversation_tracker.dart';

export '../../features/notification/domain/entities/app_notification.dart';

class NotificationInboxState {
  const NotificationInboxState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.serverTime,
    this.isAuthenticated = false,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final DateTime? serverTime;
  final bool isAuthenticated;
}

class AppNotificationService {
  AppNotificationService({
    NotificationRepository? repository,
    this.pollInterval = const Duration(seconds: 5),
    this.pageSize = 50,
  }) : _repository = repository ?? NotificationRepositoryImpl();

  static final AppNotificationService instance = AppNotificationService();

  final NotificationRepository _repository;
  final Duration pollInterval;
  final int pageSize;
  final ValueNotifier<NotificationInboxState> inbox = ValueNotifier(
    const NotificationInboxState(),
  );
  final StreamController<AppNotification> _foregroundEvents =
      StreamController<AppNotification>.broadcast();
  final Set<String> _presentedVersions = {};
  final Map<String, Future<void>> _conversationReads = {};
  Stream<AppNotification> get foregroundEvents => _foregroundEvents.stream;
  Future<void> Function(AppNotification notification)? onOpen;

  String? _userId;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  int? _refreshGeneration;
  int _loadedCount = 0;
  DateTime? _watermark;
  Timer? _pollTimer;
  Future<void>? _refreshFuture;

  void setSession(String? userId) {
    final next = userId == null || userId.isEmpty ? null : userId;
    if (_disposed || next == _userId) return;
    _generation++;
    _userId = next;
    _watermark = null;
    _loadedCount = 0;
    _presentedVersions.clear();
    _pollTimer?.cancel();
    inbox.value = NotificationInboxState(isAuthenticated: next != null);
    if (next != null && _foreground) {
      unawaited(refresh());
      _startPolling();
    }
  }

  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    _generation++;
    _watermark = null;
    _pollTimer?.cancel();
    if (foreground && _userId != null) {
      // กลับจากพื้นหลังให้โหลดเงียบ เพื่อไม่เล่นรายการที่เกิดระหว่างพักแอป
      unawaited(refresh());
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_foreground && _userId != null) {
        unawaited(refresh(silent: false));
      }
    });
  }

  Future<void> refresh({bool silent = true}) {
    if (_disposed || _userId == null) return Future<void>.value();
    if (inbox.value.isLoadingMore) return Future<void>.value();
    if (_refreshGeneration == _generation && _refreshFuture != null) {
      return _refreshFuture!;
    }
    final generation = _generation;
    _refreshGeneration = generation;
    final request = _fetch(generation, silent: silent);
    _refreshFuture = request;
    unawaited(
      request.whenComplete(() {
        if (_refreshGeneration == generation) _refreshFuture = null;
      }),
    );
    return request;
  }

  Future<void> _fetch(int generation, {required bool silent}) async {
    final previous = inbox.value;
    _publish(
      items: previous.items,
      unreadCount: previous.unreadCount,
      isLoading: previous.items.isEmpty,
      hasMore: previous.hasMore,
      serverTime: previous.serverTime,
    );
    try {
      final pagesToRefresh = (_loadedCount / pageSize).ceil().clamp(1, 1000000);
      NotificationInboxPage? firstPage;
      NotificationInboxPage? lastPage;
      final byId = <String, AppNotification>{};
      var fetchedCount = 0;
      for (var index = 0; index < pagesToRefresh; index++) {
        final page = await GetNotificationInbox(_repository)(
          limit: pageSize,
          offset: index * pageSize,
        );
        if (!_isCurrent(generation)) return;
        firstPage ??= page;
        lastPage = page;
        fetchedCount += page.items.length;
        for (final item in page.items) {
          byId.putIfAbsent(item.id, () => item);
        }
        if (page.items.length < pageSize) break;
      }
      final page = firstPage!;
      final watermark = _watermark;
      final items = byId.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _loadedCount = fetchedCount;
      _publish(
        items: List.unmodifiable(items),
        unreadCount: lastPage!.unreadCount,
        hasMore: lastPage.items.length >= pageSize,
        serverTime: page.serverTime,
      );
      _watermark = page.serverTime;
      if (!silent && watermark != null && _foreground) {
        for (final item in items.reversed) {
          if (item.updatedAt.isAfter(watermark)) _present(item);
        }
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      // เมื่อเชื่อมต่อใหม่ให้ตั้งฐานเวลาใหม่ โดยไม่เด้งประวัติจากช่วงออฟไลน์
      _watermark = null;
      _publish(
        items: previous.items,
        unreadCount: previous.unreadCount,
        hasMore: previous.hasMore,
        serverTime: previous.serverTime,
        error: _errorMessage(error),
      );
    }
  }

  Future<void> loadMore() async {
    final pending = _refreshFuture;
    if (pending != null) await pending;
    final previous = inbox.value;
    if (_disposed ||
        _userId == null ||
        !previous.hasMore ||
        previous.isLoadingMore) {
      return;
    }
    final generation = _generation;
    _publish(
      items: previous.items,
      unreadCount: previous.unreadCount,
      hasMore: true,
      isLoadingMore: true,
      serverTime: previous.serverTime,
    );
    try {
      final page = await GetNotificationInbox(_repository)(
        limit: pageSize,
        offset: _loadedCount,
      );
      if (!_isCurrent(generation)) return;
      final byId = {for (final item in inbox.value.items) item.id: item};
      for (final item in page.items) {
        byId.putIfAbsent(item.id, () => item);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _loadedCount += page.items.length;
      _publish(
        items: List.unmodifiable(merged),
        unreadCount: page.unreadCount,
        hasMore: page.items.length >= pageSize,
        serverTime: inbox.value.serverTime,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _publish(
        items: inbox.value.items,
        unreadCount: inbox.value.unreadCount,
        hasMore: true,
        serverTime: inbox.value.serverTime,
        error: _errorMessage(error),
      );
    }
  }

  Future<void> handlePush(Map<String, dynamic> data) async {
    if (_disposed || !_foreground || _userId == null) return;
    final generation = _generation;
    final watermark = _watermark;
    await refresh(silent: false);
    if (!_isCurrent(generation) || watermark == null || !_foreground) return;
    final id = data['notification_id']?.toString();
    final conversationId = data['conversation_id']?.toString();
    final eventTime = DateTime.tryParse('${data['event_at']}');
    final expiresAt = DateTime.tryParse('${data['expires_at']}');
    final serverTime = inbox.value.serverTime;
    if (expiresAt != null &&
        serverTime != null &&
        !expiresAt.isAfter(serverTime)) {
      return;
    }
    for (final item in inbox.value.items) {
      if (item.id == id ||
          (id == null &&
              conversationId != null &&
              item.conversationId == conversationId)) {
        if (!item.updatedAt.isAfter(watermark)) return;
        if (eventTime != null && item.updatedAt.isAfter(eventTime)) return;
        _present(item);
        return;
      }
    }
  }

  void _present(AppNotification item) {
    if (item.isRead || _presentedVersions.contains(item.versionKey)) return;
    _presentedVersions.add(item.versionKey);
    if (_presentedVersions.length > 500) {
      _presentedVersions.remove(_presentedVersions.first);
    }
    if (item.category == AppNotificationCategory.chat &&
        item.conversationId != null &&
        ActiveConversationTracker.instance.isConversationActive(
          item.conversationId!,
        )) {
      unawaited(markConversationRead(item.conversationId!));
      return;
    }
    _foregroundEvents.add(item);
  }

  Future<void> markRead(String id) async {
    final matches = inbox.value.items.where((item) => item.id == id);
    if (_disposed || _userId == null || matches.isEmpty) return;
    final generation = _generation;
    final notification = matches.first;
    try {
      await MarkNotificationRead(_repository)(notification);
      if (!_isCurrent(generation)) return;
      _applyRead(
        (item) =>
            item.id == id && !item.updatedAt.isAfter(notification.updatedAt),
      );
      await _refreshAfterMutation(generation);
    } catch (error) {
      if (_isCurrent(generation)) _showError(error);
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    if (_disposed || _userId == null) return;
    final generation = _generation;
    final through = inbox.value.serverTime;
    try {
      await MarkAllNotificationsRead(_repository)(readThrough: through);
      if (!_isCurrent(generation)) return;
      _applyRead((item) => through != null && !item.updatedAt.isAfter(through));
      await _refreshAfterMutation(generation);
    } catch (error) {
      if (_isCurrent(generation)) _showError(error);
      rethrow;
    }
  }

  Future<void> markConversationRead(String conversationId) {
    if (_disposed || _userId == null) return Future<void>.value();
    final key = '$_generation:$conversationId';
    final pending = _conversationReads[key];
    if (pending != null) return pending;
    final request = _markConversationRead(conversationId, _generation);
    _conversationReads[key] = request;
    unawaited(
      request.whenComplete(() {
        _conversationReads.remove(key);
      }),
    );
    return request;
  }

  Future<void> _markConversationRead(
    String conversationId,
    int generation,
  ) async {
    try {
      await _repository.markConversationRead(conversationId);
      if (!_isCurrent(generation)) return;
      await _refreshAfterMutation(generation);
    } catch (error) {
      if (_isCurrent(generation)) _showError(error);
    }
  }

  Future<void> open(AppNotification item) async {
    final generation = _generation;
    try {
      await markRead(item.id);
    } catch (_) {
      // เปิดรายละเอียดได้แม้การบันทึกอ่านแล้วขัดข้อง โดยยังแสดงข้อผิดพลาดในกล่องแจ้งเตือน
    }
    if (_isCurrent(generation)) await onOpen?.call(item);
  }

  void _applyRead(bool Function(AppNotification item) matches) {
    final previous = inbox.value;
    final at = previous.serverTime ?? DateTime.now().toUtc();
    var newlyRead = 0;
    final items = previous.items.map((item) {
      if (!item.isRead && matches(item)) {
        newlyRead += item.unreadCount;
        return item.asRead(at);
      }
      return item;
    }).toList();
    _publish(
      items: List.unmodifiable(items),
      unreadCount: (previous.unreadCount - newlyRead).clamp(
        0,
        previous.unreadCount,
      ),
      hasMore: previous.hasMore,
      serverTime: previous.serverTime,
    );
  }

  Future<void> _refreshAfterMutation(int generation) async {
    final pending = _refreshGeneration == generation ? _refreshFuture : null;
    // รอ snapshot ที่เริ่มก่อนบันทึกอ่านแล้ว เพื่อไม่ใช้คำตอบเก่าทับผลที่เพิ่งบันทึก
    if (pending != null) await pending;
    if (_isCurrent(generation)) await refresh(silent: false);
  }

  bool _isCurrent(int generation) =>
      !_disposed && _generation == generation && _userId != null;

  void _showError(Object error) {
    final current = inbox.value;
    _publish(
      items: current.items,
      unreadCount: current.unreadCount,
      hasMore: current.hasMore,
      serverTime: current.serverTime,
      error: _errorMessage(error),
    );
  }

  String _errorMessage(Object error) => error is NotificationFailure
      ? error.message
      : 'เชื่อมต่อการแจ้งเตือนไม่ได้ กรุณาลองใหม่';

  void _publish({
    required List<AppNotification> items,
    required int unreadCount,
    bool isLoading = false,
    bool isLoadingMore = false,
    bool hasMore = false,
    DateTime? serverTime,
    String? error,
  }) {
    if (_disposed) return;
    inbox.value = NotificationInboxState(
      items: items,
      unreadCount: unreadCount,
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      hasMore: hasMore,
      error: error,
      serverTime: serverTime,
      isAuthenticated: _userId != null,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _pollTimer?.cancel();
    _repository.close();
    inbox.dispose();
    unawaited(_foregroundEvents.close());
  }
}
