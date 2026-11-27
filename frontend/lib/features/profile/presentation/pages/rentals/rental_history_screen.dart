import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/usecases/get_rental_history_usecase.dart';
import '../../widgets/rentals/rental_history_widgets.dart';

class RentalHistoryScreen extends StatefulWidget {
  final GetRentalHistoryUseCase? getRentalHistoryUseCase;

  const RentalHistoryScreen({super.key, this.getRentalHistoryUseCase});

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  late final GetRentalHistoryUseCase _getRentalHistoryUseCase;
  StreamSubscription<AuthState>? _authSubscription;
  int _loadRequestId = 0;
  String? _historyUserId;
  String? _loadError;
  List<RentalHistoryItemData>? _history;

  String? get _currentUserId {
    if (!SupabaseConfig.isInitialized) return null;
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    return userId == null || userId.isEmpty ? null : userId;
  }

  @override
  void initState() {
    super.initState();
    _getRentalHistoryUseCase =
        widget.getRentalHistoryUseCase ??
        GetRentalHistoryUseCase(RentalManagementRepositoryImpl());
    _loadRentalHistory();
  }

  Future<void> _loadRentalHistory() async {
    if (!mounted) return;
    if (SupabaseConfig.isInitialized) {
      _authSubscription ??= SupabaseConfig.client.auth.onAuthStateChange.listen(
        (_) {
          if (_currentUserId != _historyUserId) {
            unawaited(_loadRentalHistory());
          }
        },
        onError: (Object _) {},
      );
    }

    final requestId = ++_loadRequestId;
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      setState(() {
        _history = null;
        _historyUserId = null;
        _loadError = SupabaseConfig.isInitialized
            ? 'กรุณาเข้าสู่ระบบเพื่อดูประวัติการเช่า'
            : 'ระบบข้อมูลการเช่ายังไม่พร้อมใช้งาน';
      });
      return;
    }

    if (currentUserId != _historyUserId || _loadError != null) {
      setState(() {
        _history = null;
        _historyUserId = currentUserId;
        _loadError = null;
      });
    }

    try {
      final bookings = await _getRentalHistoryUseCase.execute(currentUserId);
      if (!mounted || !_isCurrentLoad(requestId, currentUserId)) return;

      final completedBookingIds = bookings
          .where(
            (booking) =>
                booking.bookingId != null &&
                booking.itemId != null &&
                _isCompleted(booking.statusCode),
          )
          .map((booking) => booking.bookingId!)
          .toList();
      final reviewedBookingIds = <int>{};
      if (completedBookingIds.isNotEmpty) {
        try {
          final reviews = await SupabaseConfig.client
              .from('review_tb')
              .select('booking_id')
              .eq('user_id', currentUserId)
              .inFilter('booking_id', completedBookingIds);
          for (final review in reviews as List) {
            final bookingId = (review['booking_id'] as num?)?.toInt();
            if (bookingId != null) reviewedBookingIds.add(bookingId);
          }
        } catch (_) {
          // หากตรวจประวัติรีวิวไม่ได้ ยังให้เปิดแบบฟอร์มที่มีการตรวจซ้ำก่อนบันทึก
        }
      }
      if (!mounted || !_isCurrentLoad(requestId, currentUserId)) return;

      final List<RentalHistoryItemData> result = [];

      for (final b in bookings) {
        final (statusText, statusColor, statusBg) = _formatStatus(b.statusCode);
        String dateStr = '';
        if (b.startDate != null) {
          try {
            dateStr = DateFormat(
              'd MMM yyyy',
              'th',
            ).format(b.startDate!.toLocal());
          } catch (_) {
            dateStr =
                '${b.startDate!.day}/${b.startDate!.month}/${b.startDate!.year}';
          }
        }

        result.add(
          RentalHistoryItemData(
            bookingId: b.bookingId,
            itemId: b.itemId,
            imageUrl: b.imageUrl,
            title: b.title,
            ownerId: b.partnerId,
            ownerName: b.partnerName,
            duration: b.duration,
            date: dateStr,
            status: statusText,
            statusColor: statusColor,
            statusBgColor: statusBg,
            iconData: _mapCategoryToIcon(b.category),
            isCompleted: _isCompleted(b.statusCode),
            alreadyReviewed:
                b.bookingId != null && reviewedBookingIds.contains(b.bookingId),
          ),
        );
      }

      setState(() => _history = result);
    } catch (_) {
      if (!mounted || !_isCurrentLoad(requestId, currentUserId)) return;

      if (_history == null) {
        setState(
          () => _loadError =
              'โหลดประวัติการเช่าไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
        );
      } else {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('อัปเดตประวัติการเช่าไม่สำเร็จ'),
              action: SnackBarAction(
                label: 'ลองใหม่',
                onPressed: () {
                  if (mounted && _currentUserId == currentUserId) {
                    unawaited(_loadRentalHistory());
                  }
                },
              ),
            ),
          );
      }
    }
  }

  bool _isCurrentLoad(int requestId, String userId) =>
      requestId == _loadRequestId && _currentUserId == userId;

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  bool _isCompleted(String? status) {
    final normalized = status?.toLowerCase().trim();
    return normalized == 'completed' || normalized == 'finished';
  }

  Future<void> _openReview(RentalHistoryItemData item) async {
    if (_historyUserId != _currentUserId ||
        item.bookingId == null ||
        item.itemId == null) {
      return;
    }
    await AppRoutes.openReview(
      context,
      bookingId: item.bookingId,
      itemId: item.itemId,
      itemName: item.title,
      ownerId: item.ownerId,
      ownerName: item.ownerName,
      itemImageUrl: item.imageUrl,
    );
    if (mounted) await _loadRentalHistory();
  }

  (String, Color, Color) _formatStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'finished':
        return ('เสร็จสิ้น', const Color(0xFF2E7D32), const Color(0xFFE8F5E9));
      case 'active':
        return ('กำลังเช่า', const Color(0xFF1565C0), const Color(0xFFE3F2FF));
      case 'awaiting_return':
        return (
          'รอตรวจรับคืน',
          const Color(0xFFE65100),
          const Color(0xFFFFF3E0),
        );
      case 'return_ready':
        return (
          'รอยืนยันการคืน',
          const Color(0xFFE65100),
          const Color(0xFFFFF3E0),
        );
      case 'pending':
        return (
          'รอการยืนยัน',
          const Color(0xFFE65100),
          const Color(0xFFFFF3E0),
        );
      case 'confirmed':
        return ('ยืนยันแล้ว', const Color(0xFF2E7D32), const Color(0xFFE8F5E9));
      case 'cancelled':
        return ('ยกเลิกแล้ว', const Color(0xFFC62828), const Color(0xFFFFEBEE));
      default:
        return ('เสร็จสิ้น', const Color(0xFF2E7D32), const Color(0xFFE8F5E9));
    }
  }

  IconData _mapCategoryToIcon(String? category) {
    if (category == null) return Icons.devices_other_outlined;
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera')) {
      return Icons.camera_alt_outlined;
    }
    if (cat.contains('โดรน') || cat.contains('drone')) {
      return Icons.flight_takeoff_outlined;
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone')) {
      return Icons.smartphone_outlined;
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook')) {
      return Icons.laptop_mac_outlined;
    }
    if (cat.contains('เสียง') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio')) {
      return Icons.speaker_outlined;
    }
    if (cat.contains('แคมป์') || cat.contains('เต็นท์')) {
      return Icons.terrain_outlined;
    }
    if (cat.contains('รถ') || cat.contains('ยานยนต์')) {
      return Icons.directions_car_outlined;
    }
    if (cat.contains('เครื่องมือ') || cat.contains('tool')) {
      return Icons.build_outlined;
    }
    if (cat.contains('เสื้อ') || cat.contains('สูท')) {
      return Icons.checkroom_outlined;
    }
    return Icons.inventory_2_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final matchesAccount = _historyUserId == _currentUserId;
    final history = matchesAccount ? _history : null;
    final loadError = matchesAccount ? _loadError : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ประวัติการเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: history == null && loadError == null
          ? const RentalHistoryLoadingSkeleton()
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loadError, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadRentalHistory,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              ),
            )
          : history!.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadRentalHistory,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                itemCount: history.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = history[index];
                  return RentalHistoryCard(
                    item: item,
                    onReview: item.isCompleted && !item.alreadyReviewed
                        ? () => _openReview(item)
                        : null,
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ยังไม่มีประวัติการเช่า',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'เมื่อคุณทำการจองหรือเช่าอุปกรณ์ รายการประวัติการเช่าของคุณจะแสดงที่นี่',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.hintTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'ค้นหาอุปกรณ์เพื่อเช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
