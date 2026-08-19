import 'package:flutter/material.dart';

import '../../domain/entities/booking_request_model.dart';
import 'booking_request_page.dart';

export '../../domain/entities/booking_request_model.dart';
export 'booking_confirmation_page.dart';
export 'booking_request_page.dart';

/// หน้าหลักของ Booking Feature (ค่าเริ่มต้นเปิดหน้าคำขอการเช่า BookingRequestPage)
class BookingScreen extends StatelessWidget {
  const BookingScreen({
    super.key,
    this.initialData,
    this.itemId,
  });

  final BookingRequestData? initialData;
  final int? itemId;

  @override
  Widget build(BuildContext context) {
    return BookingRequestPage(
      initialData: initialData,
      itemId: itemId,
    );
  }
}

// Alias สำหรับความสะดวกในการเรียกใช้
typedef BookingPage = BookingScreen;
