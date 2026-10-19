import 'package:flutter/material.dart';

import '../../../../rental_return/presentation/pages/rental_return_page.dart';
import '../../../domain/usecases/update_booking_status_usecase.dart';

// จุดเรียกเดิมใช้กระบวนการคืนเดียวกัน เพื่อไม่ข้ามหลักฐานและการยืนยันจาก server
class RentalReturnModal extends StatelessWidget {
  const RentalReturnModal({
    super.key,
    this.bookingId,
    required this.itemTitle,
    required this.ownerName,
    this.itemImageUrl,
    this.renterName,
    this.depositAmount = 0,
    this.initialIsOwner = false,
    this.onReturnSuccess,
    this.updateBookingStatusUseCase,
  });
  final int? bookingId;
  final String itemTitle;
  final String ownerName;
  final String? itemImageUrl;
  final String? renterName;
  final double depositAmount;
  final bool initialIsOwner;
  final ValueChanged<String>? onReturnSuccess;
  final UpdateBookingStatusUseCase? updateBookingStatusUseCase;

  static Future<void> show(
    BuildContext context, {
    int? bookingId,
    required String itemTitle,
    required String ownerName,
    String? itemImageUrl,
    String? renterName,
    double depositAmount = 0,
    bool initialIsOwner = false,
    ValueChanged<String>? onReturnSuccess,
    UpdateBookingStatusUseCase? updateBookingStatusUseCase,
  }) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            RentalReturnPage(rentalId: bookingId, isLender: initialIsOwner),
      ),
    );
    if (completed == true) onReturnSuccess?.call('completed');
  }

  @override
  Widget build(BuildContext context) =>
      RentalReturnPage(rentalId: bookingId, isLender: initialIsOwner);
}
