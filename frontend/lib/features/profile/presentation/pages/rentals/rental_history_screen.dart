import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  bool _isLoading = true;
  List<RentalHistoryItemData> _history = [];

  @override
  void initState() {
    super.initState();
    _getRentalHistoryUseCase =
        widget.getRentalHistoryUseCase ??
        GetRentalHistoryUseCase(RentalManagementRepositoryImpl());
    _loadRentalHistory();
  }

  Future<void> _loadRentalHistory() async {
    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bookings = await _getRentalHistoryUseCase.execute(currentUserId);
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
            title: b.title,
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

      if (mounted) {
        setState(() {
          _history = result;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isCompleted(String? status) {
    final normalized = status?.toLowerCase().trim();
    return normalized == 'completed' || normalized == 'finished';
  }

  Future<void> _openReview(RentalHistoryItemData item) async {
    if (item.bookingId == null || item.itemId == null) return;
    await AppRoutes.openReview(
      context,
      bookingId: item.bookingId,
      itemId: item.itemId,
      itemName: item.title,
      ownerName: item.ownerName,
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
      body: _isLoading
          ? const RentalHistoryLoadingSkeleton()
          : _history.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadRentalHistory,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                itemCount: _history.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _history[index];
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
