import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../domain/entities/booking_request_model.dart';
import 'location_picker_map_page.dart';
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
    this.isEditMode = false,
  });

  final BookingRequestData? initialData;
  final int? itemId;
  final bool isEditMode;

  @override
  State<BookingRequestPage> createState() => _BookingRequestPageState();
}

class _BookingRequestPageState extends State<BookingRequestPage> {
  late BookingRequestData _bookingData;
  BookingRentalType? _selectedRentalType;
  bool _showRentalTypeError = false;
  bool _showRentalDatesError = false;
  bool _hasSelectedLocation = false;
  bool _showLocationError = false;
  String? _locationAddress;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _bookingData =
        widget.initialData ??
        BookingRequestData(
          item: BookingItemInfo.defaultMockItem,
          rentalType: BookingRentalType.daily,
          startDate: today,
          endDate: today.add(const Duration(days: 1)),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          location: 'ซีคอน บางแค',
          locationNote: 'เลือกโดยผู้ปล่อยเช่า',
          latitude: 13.7115884,
          longitude: 100.4341077,
        );
    _selectedRentalType = _bookingData.rentalType;
    _hasSelectedLocation = widget.isEditMode;
  }

  bool get _isRentalPeriodValid {
    if (_bookingData.rentalType == BookingRentalType.daily) {
      final start = DateTime(
        _bookingData.startDate.year,
        _bookingData.startDate.month,
        _bookingData.startDate.day,
      );
      final end = DateTime(
        _bookingData.endDate.year,
        _bookingData.endDate.month,
        _bookingData.endDate.day,
      );
      return end.isAfter(start);
    }

    final startMinutes =
        _bookingData.startTime.hour * 60 + _bookingData.startTime.minute;
    final endMinutes =
        _bookingData.endTime.hour * 60 + _bookingData.endTime.minute;
    return endMinutes > startMinutes;
  }

  void _onRentalTypeChanged(BookingRentalType type) {
    setState(() {
      _selectedRentalType = type;
      _showRentalTypeError = false;
      DateTime newEnd = _bookingData.endDate;
      if (type == BookingRentalType.daily) {
        final start = DateTime(
          _bookingData.startDate.year,
          _bookingData.startDate.month,
          _bookingData.startDate.day,
        );
        final end = DateTime(
          _bookingData.endDate.year,
          _bookingData.endDate.month,
          _bookingData.endDate.day,
        );
        if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
          newEnd = start.add(const Duration(days: 1));
        }
      }
      _bookingData = _bookingData.copyWith(rentalType: type, endDate: newEnd);
    });
  }

  void _onDatesChanged(DateTime start, DateTime end) {
    setState(() {
      _showRentalDatesError = false;
      _bookingData = _bookingData.copyWith(startDate: start, endDate: end);
    });
  }

  void _onTimesChanged(TimeOfDay start, TimeOfDay end) {
    setState(() {
      _showRentalDatesError = false;
      _bookingData = _bookingData.copyWith(startTime: start, endTime: end);
    });
  }

  void _onLocationChanged(String newLocation) {
    setState(() {
      _hasSelectedLocation = true;
      _showLocationError = false;
      _locationAddress = null;
      _bookingData = _bookingData.copyWith(
        location: newLocation,
        locationNote: 'ระบุโดยคุณ',
      );
    });
  }

  void _onLocationResultChanged(LocationPickerResult result) {
    setState(() {
      _hasSelectedLocation = true;
      _showLocationError = false;
      _locationAddress = result.fullAddress;
      _bookingData = _bookingData.copyWith(
        location: result.locationName,
        locationNote: result.locationNote,
        latitude: result.latitude,
        longitude: result.longitude,
      );
    });
  }

  Future<void> _submitBookingRequestToChat(BuildContext sheetContext) async {
    setState(() => _isSubmitting = true);

    if (Navigator.canPop(sheetContext)) {
      Navigator.pop(sheetContext);
    }

    try {
      final payload = _bookingData.toChatMessagePayload();
      final chatDataSource = ChatRemoteDataSource();

      String? convId = _bookingData.conversationId;

      if (convId == null || convId.isEmpty) {
        if (_bookingData.ownerId != null && _bookingData.ownerId!.isNotEmpty) {
          try {
            final conversation = await chatDataSource.getOrCreateConversation(
              itemId: _bookingData.item.id,
              ownerId: _bookingData.ownerId!,
            );
            convId = conversation.id;
          } catch (_) {}
        }
      }

      if (convId != null && convId.isNotEmpty) {
        final oldMsgId = _bookingData.originalMessageId;
        if (widget.isEditMode && oldMsgId != null && oldMsgId.isNotEmpty) {
          // อัปเดตข้อมูลบนการ์ดคำขอเช่าเดิมในแชททันทีโดยไม่ต้องส่งการ์ดใหม่
          try {
            await chatDataSource.editMessage(
              messageId: oldMsgId,
              newMessage: payload,
              conversationId: convId,
            );
          } catch (_) {
            await chatDataSource.sendMessage(
              conversationId: convId,
              message: payload,
              imageUrl: _bookingData.item.imageUrl.isNotEmpty
                  ? _bookingData.item.imageUrl
                  : null,
            );
          }
        } else {
          await chatDataSource.sendMessage(
            conversationId: convId,
            message: payload,
            imageUrl: _bookingData.item.imageUrl.isNotEmpty
                ? _bookingData.item.imageUrl
                : null,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditMode
                  ? 'บันทึกการแก้ไขและอัปเดตข้อมูลในแชทเรียบร้อยแล้ว'
                  : 'ส่งคำขอการเช่าไปยังแชทเรียบร้อยแล้ว',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.maybePop(context, _bookingData);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ส่งคำขอสำเร็จ: ${e.toString()}'),
            backgroundColor: AppColors.primaryColor,
          ),
        );
        Navigator.maybePop(context, _bookingData);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _handleSendBookingRequest() {
    final hasValidationError =
        _selectedRentalType == null ||
        !_isRentalPeriodValid ||
        !_hasSelectedLocation;

    if (hasValidationError) {
      setState(() {
        _showRentalTypeError = _selectedRentalType == null;
        _showRentalDatesError = !_isRentalPeriodValid;
        _showLocationError = !_hasSelectedLocation;
      });
      return;
    }

    // แสดง Bottom Sheet สรุปตรวจสอบรายละเอียดก่อนส่งคำขอไปยังแชท
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // สัญลักษณ์ Drag Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // หัวข้อ
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isEditMode
                            ? Icons.edit_note_rounded
                            : Icons.receipt_long_rounded,
                        color: AppColors.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isEditMode
                                ? 'ตรวจสอบรายละเอียดการแก้ไข'
                                : 'ตรวจสอบรายละเอียดคำขอเช่า',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E2022),
                            ),
                          ),
                          Text(
                            widget.isEditMode
                                ? 'ระบบจะส่งข้อมูลที่แก้ไขเข้าห้องแชท'
                                : 'ระบบจะส่งการ์ดคำขอนี้เข้าห้องแชททันที',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12.5,
                              color: Color(0xFF777A7C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // กล่องสรุปรายละเอียด
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // สินค้า
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 52,
                              height: 52,
                              color: const Color(0xFFEDF2F7),
                              child: _bookingData.item.imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _bookingData.item.imageUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => const Icon(
                                        Icons.image_not_supported_outlined,
                                        color: Color(0xFF94A3B8),
                                        size: 24,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.inventory_2_outlined,
                                      color: Color(0xFF94A3B8),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _bookingData.item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E2022),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _bookingData.rentalType ==
                                          BookingRentalType.daily
                                      ? 'รายวัน (${_bookingData.item.dailyRate.toStringAsFixed(0)} ฿/วัน)'
                                      : 'รายชั่วโมง (${_bookingData.item.hourlyRate.toStringAsFixed(0)} ฿/ชม.)',
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12,
                                    color: AppColors.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),

                      // เวลา
                      _buildSummaryItem(
                        icon: Icons.access_time_filled_rounded,
                        iconColor: const Color(0xFF8B5CF6),
                        label: 'เวลาเช่า:',
                        value: _bookingData.formattedPeriodSummary,
                      ),
                      const SizedBox(height: 8),

                      // สถานที่
                      _buildSummaryItem(
                        icon: Icons.location_on_rounded,
                        iconColor: const Color(0xFFEF4444),
                        label: 'สถานที่นัดพบ:',
                        value: _bookingData.location,
                      ),
                      const SizedBox(height: 8),

                      // ยอดรวม
                      _buildSummaryItem(
                        icon: Icons.payments_rounded,
                        iconColor: const Color(0xFF10B981),
                        label: 'ยอดรวม:',
                        value:
                            '${_bookingData.totalPrice.toStringAsFixed(0)} ฿',
                        isHighlight: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ข้อความเตือนความปลอดภัย "ให้ตรวจสอบรายละเอียดอย่างถี่ถ้วน"
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFDE68A),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ให้ตรวจสอบรายละเอียดอย่างถี่ถ้วน ก่อนยืนยันการส่งคำขอ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ปุ่ม "ยืนยันและส่งคำขอ"
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    key: const ValueKey('confirm-send-booking-request-button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    onPressed: _isSubmitting
                        ? null
                        : () => _submitBookingRequestToChat(ctx),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.isEditMode
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.send_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.isEditMode
                                    ? 'ยืนยันและส่งข้อมูลที่แก้ไข'
                                    : 'ยืนยันและส่งคำขอเข้าแชท',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),

                // ปุ่ม "กลับไปแก้ไข"
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'กลับไปแก้ไขข้อมูล',
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

  Widget _buildSummaryItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              color: isHighlight
                  ? AppColors.primaryColor
                  : const Color(0xFF1E2022),
            ),
          ),
        ),
      ],
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
        title: Text(
          widget.isEditMode ? 'แก้ไขรายละเอียดการเช่า' : 'คำขอการเช่า',
          style: const TextStyle(
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
            // การ์ดสินค้าอยู่คงที่ด้านบน ไม่เลื่อนตามรายละเอียดคำขอ
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: BookingProductCard(item: _bookingData.item),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. ตัวเลือกรูปแบบการเช่า (Dropdown: ต่อชั่วโมง / ต่อวัน)
                    BookingTypeDropdown(
                      selectedType: _selectedRentalType,
                      onChanged: _onRentalTypeChanged,
                      showError: _showRentalTypeError,
                    ),
                    const SizedBox(height: 18),

                    // 2. ตัวเลือกช่วงเวลา / วันที่เช่า
                    BookingTimeRangePicker(
                      rentalType: _bookingData.rentalType,
                      startDate: _bookingData.startDate,
                      endDate: _bookingData.endDate,
                      startTime: _bookingData.startTime,
                      endTime: _bookingData.endTime,
                      onDatesChanged: _onDatesChanged,
                      onTimesChanged: _onTimesChanged,
                      showDateError: _showRentalDatesError,
                    ),
                    const SizedBox(height: 18),

                    // 3. สถานที่นัดพบ (Meeting Location)
                    BookingLocationCard(
                      location: _bookingData.location,
                      locationNote: _bookingData.locationNote,
                      locationAddress: _locationAddress,
                      latitude: _bookingData.latitude,
                      longitude: _bookingData.longitude,
                      onLocationResultChanged: _onLocationResultChanged,
                      onLocationChanged: _onLocationChanged,
                      showError: _showLocationError,
                    ),
                    const SizedBox(height: 18),

                    // 4. สรุปราคา (Price Summary)
                    BookingPriceSummaryCard(bookingData: _bookingData),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // 5. ปุ่มด้านล่าง: "แก้ไข" (ฝั่งผู้ปล่อยเช่า) หรือ "ส่งคำขอการเช่า"
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  key: const ValueKey('submit-booking-request-button'),
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
                  child: Text(
                    widget.isEditMode ? 'แก้ไข' : 'ส่งคำขอการเช่า',
                    style: const TextStyle(
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
