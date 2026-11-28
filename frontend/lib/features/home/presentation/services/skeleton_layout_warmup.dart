import 'dart:async';
import 'dart:ui';

import '../../../../core/network/auth_session.dart';
import '../../../../core/services/skeleton_layout_cache.dart';
import '../../../chat/domain/entities/chat_conversation.dart';
import '../../../chat/domain/repositories/chat_repository.dart';
import '../../../chat/presentation/widgets/chat_skeleton_layout_estimate.dart';
import '../../../notification/data/notification_remote_data_source.dart';
import '../../../profile/data/repositories/promptpay_account_repository.dart';
import '../../../profile/data/repositories/rental_management_repository_impl.dart';
import '../../../profile/data/repositories/user_items_repository_impl.dart';
import '../../../profile/domain/usecases/get_favorites_usecase.dart';
import '../../../profile/domain/usecases/get_my_items_usecase.dart';
import '../../../profile/domain/usecases/get_rental_bookings_usecase.dart';
import '../../../profile/domain/usecases/get_rental_history_usecase.dart';

/// เตรียมรูปร่าง skeleton ล่วงหน้าหลังเข้าสู่ระบบ สำหรับหน้าที่ผู้ใช้ยังไม่เคยเปิด
///
/// skeleton จะตรงกับข้อมูลจริงก็ต่อเมื่อรู้ว่าหน้านั้นมีกี่รายการและเป็นแบบไหน
/// ถ้ารอให้ผู้ใช้เปิดหน้าก่อน ครั้งแรกจะต้องเดา จึงดึงข้อมูลชุดเดียวกับหน้าจริงไว้เบื้องหลัง
/// เฉพาะ key ที่ยังไม่มีค่า และทำครั้งเดียวต่อผู้ใช้ต่อการเปิดแอป
class SkeletonLayoutWarmup {
  SkeletonLayoutWarmup._();

  static final instance = SkeletonLayoutWarmup._();

  final _cache = SkeletonLayoutCache.instance;
  String? _warmedUserId;
  final _warmedChats = <String>{};

  /// ดึงจำนวนรายการของหน้าโปรไฟล์และแจ้งเตือนที่ยังไม่มีรูปร่างเก็บไว้
  Future<void> warmScreens() async {
    final userId = AuthSession.userId;
    if (userId == null || _warmedUserId == userId) return;
    _warmedUserId = userId;
    await Future.wait([
      _warm('notifications.$userId', () async {
        final token = AuthSession.accessToken;
        if (token == null) return null;
        // หน้าจริงโหลดครั้งละ 40 แต่ skeleton ใช้ไม่เกิน 8 รายการแรก
        final items = await NotificationRemoteDataSource().fetch(
          token,
          limit: 8,
          offset: 0,
        );
        return [for (final item in items) item.isRead ? 'r' : 'u'];
      }),
      _warm('promptpay.$userId', () async {
        // ใช้รูปแบบเดียวกับหน้าแก้ไขพร้อมเพย์: ประเภท เลขท้ายบัตร และมีค่าบันทึกไว้หรือไม่
        final account = await PromptPayAccountRepository().load();
        return [
          account.usesNationalId ? 'n' : 'p',
          account.nationalIdLastFour == null ? '-' : '4',
          (account.phone ?? '').isEmpty ? '-' : 'v',
        ];
      }),
      _warmCount(
        'my_items.$userId',
        () async => (await GetMyItemsUseCase(
          UserItemsRepositoryImpl(),
        ).execute(userId)).length,
      ),
      _warmCount(
        'favorites.$userId',
        () async => (await GetFavoritesUseCase(
          UserItemsRepositoryImpl(),
        ).execute()).length,
      ),
      _warmCount(
        'rental_history.$userId',
        () async => (await GetRentalHistoryUseCase(
          RentalManagementRepositoryImpl(),
        ).execute(userId)).length,
      ),
      _warmCount('rental_status.$userId', () async {
        final renting = await GetRentalBookingsUseCase(
          RentalManagementRepositoryImpl(),
        ).executeRenting(userId);
        // ตัดสถานะที่จบแล้วออกเหมือน RentalStatusCubit
        const finished = {
          'rejected',
          'reject',
          'completed',
          'finished',
          'คืนของสำเร็จ',
        };
        return renting
            .where((b) => !finished.contains(b.statusCode.toLowerCase().trim()))
            .length;
      }),
    ]);
  }

  /// เมื่อรายการแชทโหลดเสร็จ จำจำนวนไว้ให้หน้าแชท และประมาณรูปร่างข้อความ
  /// ของห้องล่าสุดที่ยังไม่เคยเปิด ให้ skeleton ห้องแชทครั้งแรกใกล้ของจริง
  Future<void> warmChats(
    List<ChatConversation> conversations,
    ChatRepository repository,
  ) async {
    final userId = AuthSession.userId;
    if (userId == null) return;
    _cache.writeCount('chat_list.$userId', conversations.length);
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    final recent = conversations
        .where(
          (c) =>
              _cache.read(chatSkeletonLayoutKey(c.id)) == null &&
              _warmedChats.add(c.id),
        )
        .take(5);
    await Future.wait([
      for (final conversation in recent)
        _warm(chatSkeletonLayoutKey(conversation.id), () async {
          final messages = await repository.fetchMessages(
            conversationId: conversation.id,
            limit: 12,
          );
          return estimateChatSkeletonLayout(
            messages,
            screenWidth: size.width,
            screenHeight: size.height,
          );
        }, max: 12),
    ]);
  }

  Future<void> _warmCount(String key, Future<int> Function() load) =>
      _warm(key, () async => List.filled((await load()).clamp(0, 8), '1'));

  /// เติมค่าเฉพาะ key ที่ยังว่าง ความผิดพลาดไม่กระทบผู้ใช้ เพราะหน้าจริงจะเขียนค่าเองตอนเปิด
  Future<void> _warm(
    String key,
    Future<List<String>?> Function() load, {
    int max = 8,
  }) async {
    if (_cache.read(key) != null) return;
    try {
      final tokens = await load();
      if (tokens != null && _cache.read(key) == null) {
        _cache.write(key, tokens, max: max);
      }
    } catch (_) {}
  }
}
