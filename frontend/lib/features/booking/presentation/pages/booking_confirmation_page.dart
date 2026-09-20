import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';
import '../../domain/entities/rental_request.dart';
import '../bloc/rental_request_cubit.dart';
import '../bloc/rental_request_state.dart';
import '../widgets/booking_location_card.dart';
import '../widgets/booking_payment_method_card.dart';
import '../widgets/booking_price_summary_card.dart';
import '../widgets/booking_product_card.dart';
import '../widgets/booking_security_badge.dart';
import '../widgets/booking_time_range_picker.dart';

class BookingConfirmationPage extends StatefulWidget {
  const BookingConfirmationPage({
    super.key,
    this.bookingData,
    this.isDetailView = false,
  });

  final BookingRequestData? bookingData;
  final bool isDetailView;

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  late BookingRequestData _bookingData;
  String _selectedPaymentMethod = 'cash';
  bool _didShowSuccess = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _bookingData =
        widget.bookingData ??
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
    _selectedPaymentMethod = _bookingData.paymentMethod;
  }

  RentalRequestDraft _buildRentalDraft() {
    return RentalRequestDraft(
      itemId: _bookingData.item.id,
      startAt: _bookingData.startDateTime,
      endAt: _bookingData.endDateTime,
      rentalType: _bookingData.rentalType.name,
      pickupLocation: _bookingData.location,
    );
  }

  Future<void> _showSuccess() async {
    if (_didShowSuccess || !mounted) return;
    _didShowSuccess = true;

    // บันทึกว่าคำขอเช่าอุปกรณ์นี้ได้รับการกดยืนยันแล้ว
    await BookingConfirmationTracker.markConfirmed(
      messageId: _bookingData.originalMessageId ?? '',
      itemId: _bookingData.item.id,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ส่งคำขอเช่าเรียบร้อยแล้ว',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'คำขอของคุณถูกส่งไปยังเจ้าของอุปกรณ์แล้ว',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              // Payment notice banner (Swiss clean neutral)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ยังไม่มีการหักเงินในขั้นตอนนี้',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'คุณเลือกชำระด้วย ${_selectedPaymentMethod == 'promptpay' ? 'พร้อมเพย์ (PromptPay)' : 'เงินสด (Cash)'} โดยจะชำระเงินในวันนัดรับของจริง หลังตรวจเช็กสภาพอุปกรณ์เรียบร้อยแล้วเท่านั้น',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Tabular Key-Value Summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(
                      label: 'อุปกรณ์',
                      value: _bookingData.item.title,
                    ),
                    const SizedBox(height: 10),
                    _buildSummaryRow(
                      label: 'ระยะเวลา',
                      value: _bookingData.formattedPeriodSummary,
                    ),
                    const SizedBox(height: 10),
                    _buildSummaryRow(
                      label: 'สถานที่นัดรับ',
                      value: _bookingData.location,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                    ),
                    _buildSummaryRow(
                      label: 'ยอดชำระเมื่อรับของ',
                      value: '${_bookingData.totalPrice.toStringAsFixed(0)} ฿',
                      isBold: true,
                      valueColor: AppColors.primaryColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Next steps list (Typographic 01, 02, 03)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ขั้นตอนต่อไป',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildStepRow('01', 'นัดรับและตรวจสอบอุปกรณ์ตามที่ระบุ'),
                    const SizedBox(height: 8),
                    _buildStepRow('02', 'ชำระเงิน'),
                    const SizedBox(height: 8),
                    _buildStepRow('03', 'สแกน QR Code หรือใส่รหัส PIN เพื่อเริ่มการเช่า'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.maybePop(context, true);
                    AppRoutes.openRentalStatus(context);
                  },
                  child: const Text(
                    'ตรวจสอบสถานะการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) {
      Navigator.maybePop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          widget.isDetailView ? 'รายละเอียดที่นัดรับ' : 'ยืนยันคำขอเช่า',
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
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.isDetailView) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF10B981),
                              size: 24,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ยืนยันการนัดรับเรียบร้อยแล้ว',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF065F46),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'โปรดตรวจสอบวันเวลาและจุดนัดรับอุปกรณ์ด้านล่าง',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 12,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    BookingProductCard(item: _bookingData.item),
                    const SizedBox(height: 18),
                    BookingTimeRangePicker(
                      rentalType: _bookingData.rentalType,
                      startDate: _bookingData.startDate,
                      endDate: _bookingData.endDate,
                      startTime: _bookingData.startTime,
                      endTime: _bookingData.endTime,
                      isEditable: false,
                    ),
                    const SizedBox(height: 18),
                    BookingLocationCard(
                      location: _bookingData.location,
                      locationNote: _bookingData.locationNote,
                      latitude: _bookingData.latitude,
                      longitude: _bookingData.longitude,
                      isEditable: false,
                    ),
                    const SizedBox(height: 18),
                    BookingPriceSummaryCard(bookingData: _bookingData),
                    const SizedBox(height: 18),
                    BookingPaymentMethodCard(
                      selectedMethod: _selectedPaymentMethod,
                      isEditable: !widget.isDetailView,
                      onMethodChanged: widget.isDetailView
                          ? null
                          : (method) {
                              setState(() {
                                _selectedPaymentMethod = method;
                                _bookingData = _bookingData.copyWith(
                                  paymentMethod: method,
                                );
                              });
                            },
                    ),
                    const SizedBox(height: 20),
                    const BookingSecurityBadge(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: widget.isDetailView
                  ? SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        key: const ValueKey('view-route-on-map-button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        onPressed: () {
                          AppRoutes.openRentalTrackingMap(
                            context,
                            bookingData: _bookingData,
                          );
                        },
                        icon: const Icon(Icons.near_me_rounded, size: 20),
                        label: const Text(
                          'ดูเส้นทางนัดรับบนแผนที่',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : BlocBuilder<RentalRequestCubit, RentalRequestState>(
                      builder: (context, state) {
                        final isSubmitting =
                            state.status == RentalRequestStatus.submitting;
                        final isSuccess =
                            state.status == RentalRequestStatus.success;
                        return SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            key: const ValueKey('submit-rental-request-button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.primaryColor
                                  .withValues(alpha: 0.55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : isSuccess
                                ? () => AppRoutes.openRentalStatus(context)
                                : () =>
                                    context.read<RentalRequestCubit>().submit(
                                          _buildRentalDraft(),
                                        ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (isSuccess) ...[
                                        const Icon(
                                          Icons.assignment_outlined,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        isSuccess ? 'ตรวจสอบสถานะ' : 'ส่งคำขอเช่า',
                                        style: const TextStyle(
                                          fontFamily: AppTextStyles.fontFamily,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.isDetailView) {
      return scaffold;
    }

    return BlocListener<RentalRequestCubit, RentalRequestState>(
      listener: (context, state) {
        if (state.status == RentalRequestStatus.success) {
          unawaited(_showSuccess());
        }
        final errorMessage = state.errorMessage;
        if (errorMessage != null && errorMessage.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      },
      child: scaffold,
    );
  }

  Widget _buildSummaryRow({
    IconData? icon,
    required String label,
    required String value,
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              color: Color(0xFF334155),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

