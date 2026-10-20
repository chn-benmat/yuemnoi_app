import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
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
    this.isEditMode = false,
    this.onSendRequest,
  });

  final BookingRequestData? initialData;
  final int? itemId;
  final bool isEditMode;
  final ValueChanged<BookingRequestData>? onSendRequest;

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
    _hasSelectedLocation =
        _bookingData.latitude != null && _bookingData.longitude != null;
    _locationAddress = _bookingData.locationAddress;
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

  Future<void> _submitBookingRequestToChat(BuildContext sheetContext) async {
    setState(() => _isSubmitting = true);

    if (Navigator.canPop(sheetContext)) {
      Navigator.pop(sheetContext);
    }

    try {
      if (!widget.isEditMode && widget.onSendRequest != null) {
        widget.onSendRequest!(_bookingData);
        if (mounted) Navigator.maybePop(context, _bookingData);
        return;
      }
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

      if (convId == null || convId.isEmpty) {
        throw const ChatRemoteException('ไม่พบห้องแชตสำหรับส่งคำขอ');
      }
      if (convId.isNotEmpty) {
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
            content: Text('ส่งคำขอไม่สำเร็จ: ${e.toString()}'),
            backgroundColor: AppColors.primaryColor,
          ),
        );
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

                // หัวข้อ (Swiss Style Typography Header)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isEditMode
                          ? 'ตรวจสอบรายละเอียดการแก้ไข'
                          : 'ตรวจสอบรายละเอียดคำขอเช่า',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.isEditMode
                          ? 'ระบบจะส่งข้อมูลที่แก้ไขเข้าห้องแชท'
                          : 'ระบบจะส่งการ์ดคำขอนี้เข้าห้องแชททันที',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // การ์ดสรุปข้อมูลสไตล์ Clean SaaS
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // ส่วนแสดงสินค้า
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 46,
                              height: 46,
                              color: const Color(0xFFEDF2F7),
                              child: _bookingData.item.imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _bookingData.item.imageUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => const Icon(
                                        Icons.inventory_2_outlined,
                                        color: Color(0xFF94A3B8),
                                        size: 22,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.inventory_2_outlined,
                                      color: Color(0xFF94A3B8),
                                      size: 22,
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
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _bookingData.rentalType ==
                                          BookingRentalType.daily
                                      ? 'ค่าเช่ารายวัน (${_bookingData.item.dailyRate.toStringAsFixed(0)} ฿/วัน)'
                                      : 'ค่าเช่ารายชั่วโมง (${_bookingData.item.hourlyRate.toStringAsFixed(0)} ฿/ชม.)',
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),

                      // รายการข้อมูล Key-Value เรียบคม
                      _buildSummaryItem(
                        label: 'ระยะเวลาเช่า',
                        value: _bookingData.formattedPeriodSummary,
                      ),
                      const SizedBox(height: 9),

                      _buildSummaryItem(
                        label: 'สถานที่นัดพบ',
                        value: _bookingData.location,
                      ),
                      const SizedBox(height: 9),

                      _buildSummaryItem(
                        label: 'ยอดรวมสุทธิ',
                        value:
                            '${_bookingData.totalPrice.toStringAsFixed(0)} ฿',
                        isHighlight: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // แถบข้อความระบุเงื่อนไข เรียบง่าย คมชัด ไม่ใช่กล่องเหลือง AI Slop
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF64748B),
                        size: 15,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'โปรดตรวจสอบความถูกต้องของวันและสถานที่นัดพบก่อนส่งคำขอ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ปุ่มยืนยันและส่งคำขอ
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const ValueKey('confirm-send-booking-request-button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting
                        ? null
                        : () => _submitBookingRequestToChat(ctx),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.isEditMode
                                ? 'ยืนยันและส่งข้อมูลที่แก้ไข'
                                : 'ยืนยันและส่งคำขอเข้าแชท',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),

                // ปุ่มกลับไปแก้ไข
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'กลับไปแก้ไขข้อมูล',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
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
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: isHighlight ? 14 : 12.5,
              fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
              color: isHighlight
                  ? AppColors.primaryColor
                  : const Color(0xFF0F172A),
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
                      isEditable: false,
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
