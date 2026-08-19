import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';
import '../widgets/booking_location_card.dart';
import '../widgets/booking_price_summary_card.dart';
import '../widgets/booking_product_card.dart';
import '../widgets/booking_time_range_picker.dart';
import '../widgets/booking_type_dropdown.dart';

class BookingRequestPage extends StatefulWidget {
  const BookingRequestPage({
    super.key,
    this.initialData,
    this.itemId,
  });

  final BookingRequestData? initialData;
  final int? itemId;

  @override
  State<BookingRequestPage> createState() => _BookingRequestPageState();
}

class _BookingRequestPageState extends State<BookingRequestPage> {
  late BookingRequestData _bookingData;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _bookingData = widget.initialData ??
        BookingRequestData(
          item: BookingItemInfo.defaultMockItem,
          rentalType: BookingRentalType.daily,
          startDate: today,
          endDate: today.add(const Duration(days: 1)),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'ซีคอน บางแค',
          locationNote: 'เลือกโดยผู้ปล่อยเช่า',
        );
  }

  void _onRentalTypeChanged(BookingRentalType type) {
    setState(() {
      _bookingData = _bookingData.copyWith(rentalType: type);
    });
  }

  void _onDatesChanged(DateTime start, DateTime end) {
    setState(() {
      _bookingData = _bookingData.copyWith(
        startDate: start,
        endDate: end,
      );
    });
  }

  void _onTimesChanged(TimeOfDay start, TimeOfDay end) {
    setState(() {
      _bookingData = _bookingData.copyWith(
        startTime: start,
        endTime: end,
      );
    });
  }

  void _onLocationChanged(String newLocation) {
    setState(() {
      _bookingData = _bookingData.copyWith(
        location: newLocation,
        locationNote: 'ระบุโดยคุณ',
      );
    });
  }

  void _handleSendBookingRequest() {
    // แสดง Bottom Sheet แจ้งผลการส่งคำขอการเช่า (พร้อมปุ่มจำลองไปหน้ากดยืนยันการจอง/ชำระเงิน)
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primaryColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ส่งคำขอการเช่าเรียบร้อยแล้ว',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2022),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'คำขอการเช่าของคุณถูกส่งไปยังห้องแชทแล้ว\nเมื่อผู้ปล่อยเช่ายืนยัน จะสามารถดำเนินการชำระเงินต่อได้',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: const Color(0xFF777A7C),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                // ปุ่มทดสอบเปิดหน้ายืนยันการจอง / ชำระเงิน (ฝั่งผู้เช่ากดยืนยัน)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      AppRoutes.openBookingConfirmation(
                        context,
                        bookingData: _bookingData,
                      );
                    },
                    child: const Text(
                      'ดูหน้ายืนยันการจอง & ชำระเงิน (Preview)',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.maybePop(context);
                    },
                    child: const Text(
                      'กลับสู่หน้าแชท',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF777A7C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'คำขอการเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. การ์ดสินค้า (Product Card)
                    BookingProductCard(item: _bookingData.item),
                    const SizedBox(height: 18),

                    // 2. ตัวเลือกรูปแบบการเช่า (Dropdown: ต่อชั่วโมง / ต่อวัน)
                    BookingTypeDropdown(
                      selectedType: _bookingData.rentalType,
                      onChanged: _onRentalTypeChanged,
                    ),
                    const SizedBox(height: 18),

                    // 3. ตัวเลือกช่วงเวลา / วันที่เช่า
                    BookingTimeRangePicker(
                      rentalType: _bookingData.rentalType,
                      startDate: _bookingData.startDate,
                      endDate: _bookingData.endDate,
                      startTime: _bookingData.startTime,
                      endTime: _bookingData.endTime,
                      onDatesChanged: _onDatesChanged,
                      onTimesChanged: _onTimesChanged,
                    ),
                    const SizedBox(height: 18),

                    // 4. สถานที่นัดพบ (Meeting Location)
                    BookingLocationCard(
                      location: _bookingData.location,
                      locationNote: _bookingData.locationNote,
                      onLocationChanged: _onLocationChanged,
                    ),
                    const SizedBox(height: 18),

                    // 5. สรุปราคา (Price Summary)
                    BookingPriceSummaryCard(bookingData: _bookingData),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // 6. ปุ่มด้านล่าง: "ส่งคำขอการเช่า"
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shadowColor: AppColors.primaryColor.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: _handleSendBookingRequest,
                  child: const Text(
                    'ส่งคำขอการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
