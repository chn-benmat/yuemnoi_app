import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../core/services/location_service.dart';
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
  bool _isConfirmationSheetOpen = false;

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
    final destination = LocationService.resolveCoordinates(
      locationName: _bookingData.location,
      latitude: _bookingData.latitude ?? _bookingData.item.latitude,
      longitude: _bookingData.longitude ?? _bookingData.item.longitude,
    );
    if ((_bookingData.latitude ?? _bookingData.item.latitude) != null &&
        (_bookingData.longitude ?? _bookingData.item.longitude) != null) {
      unawaited(LocationService.instance.preloadDrivingRoute(destination));
    }
  }

  bool get _isCurrentUserOwner {
    if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized)
      return false;
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return _bookingData.ownerId != null &&
        _bookingData.ownerId == currentUserId;
  }

  RentalRequestDraft _buildRentalDraft() {
    return RentalRequestDraft(
      itemId: _bookingData.item.id,
      startAt: _bookingData.startDateTime,
      endAt: _bookingData.endDateTime,
      rentalType: _bookingData.rentalType.name,
      pickupLocation: _bookingData.location,
      offerMessageId: _bookingData.originalMessageId,
      bookingId: _bookingData.bookingId,
    );
  }

  Future<void> _showConfirmation([int? pendingBookingId]) async {
    if (_isConfirmationSheetOpen ||
        !mounted ||
        pendingBookingId == null ||
        pendingBookingId <= 0)
      return;
    _isConfirmationSheetOpen = true;
    final effectiveBookingId = pendingBookingId;
    final cubit = context.read<RentalRequestCubit>();

    final messageId = _bookingData.originalMessageId ?? '';

    final orderNumberStr = BookingConfirmationTracker.formatOrderNumber(
      effectiveBookingId,
    );

    if (!mounted) return;

    final openStatus = await showModalBottomSheet<bool>(
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
              Text(
                'ตรวจสอบและยืนยันการเช่า',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'กรุณาตรวจสอบรายละเอียดก่อนกดยืนยันการเช่า',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              // ป้ายเลขออเดอร์เด่นชัดเจน
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        size: 15,
                        color: Color(0xFF15803D),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'เลขออเดอร์: #$orderNumberStr',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                      label: 'เลขออเดอร์',
                      value: '#$orderNumberStr',
                      isBold: true,
                      valueColor: const Color(0xFF15803D),
                    ),
                    const SizedBox(height: 10),
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
                    _buildStepRow(
                      '03',
                      'สแกน QR Code หรือใส่รหัส PIN เพื่อเริ่มการเช่า',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildConfirmButton(
                sheetContext,
                cubit,
                effectiveBookingId,
                messageId,
              ),
            ],
          ),
        ),
      ),
    );

    _isConfirmationSheetOpen = false;
    if (!mounted || openStatus != true) return;
    // รอปิดแผ่นยืนยันก่อนเปิดหน้าใหม่ เพื่อไม่ให้ Navigator รับคำสั่งซ้อนกัน
    await AppRoutes.openRentalStatus(context);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildConfirmButton(
    BuildContext sheetContext,
    RentalRequestCubit cubit,
    int bookingId,
    String messageId,
  ) {
    return BlocBuilder<RentalRequestCubit, RentalRequestState>(
      bloc: cubit,
      builder: (context, state) {
        final isConfirming =
            state.status == RentalRequestStatus.confirming ||
            state.status == RentalRequestStatus.confirmed;
        return PopScope(
          canPop: !isConfirming,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.errorMessage != null) ...[
                Text(
                  state.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  key: const ValueKey('confirm-rental-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isConfirming
                      ? null
                      : () async {
                          final confirmed = await cubit.confirm(
                            offerMessageId: messageId,
                          );
                          if (!confirmed) return;
                          // บันทึกในเครื่องหลัง server ยืนยันสำเร็จเท่านั้น การเปิดหรือปิดสรุปยังคง pending
                          await BookingConfirmationTracker.markConfirmed(
                            messageId: messageId,
                            itemId: _bookingData.item.id,
                            bookingId: bookingId,
                          );
                          await BookingConfirmationTracker.setStatus(
                            messageId: messageId,
                            status: cubit.state.rentalStatus ?? 'confirmed',
                          );
                          if (sheetContext.mounted &&
                              ModalRoute.of(sheetContext)?.isCurrent == true)
                            Navigator.pop(sheetContext, true);
                        },
                  child: isConfirming
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ยืนยันการเช่า',
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
        );
      },
    );
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
          widget.isDetailView
              ? 'รายละเอียดที่นัดรับ'
              : (_isCurrentUserOwner
                    ? 'ตรวจสอบและยอมรับคำขอเช่า'
                    : 'ยืนยันคำขอเช่า'),
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
                      locationAddress: _bookingData.locationAddress,
                      latitude:
                          _bookingData.latitude ?? _bookingData.item.latitude,
                      longitude:
                          _bookingData.longitude ?? _bookingData.item.longitude,
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
                            state.status == RentalRequestStatus.submitting ||
                            state.status == RentalRequestStatus.confirming;
                        final isConfirmed =
                            state.status == RentalRequestStatus.confirmed;
                        final hasPendingRental = state.rentalId != null;
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
                            onPressed: isSubmitting || _isCurrentUserOwner
                                ? null
                                : isConfirmed
                                ? () => AppRoutes.openRentalStatus(context)
                                : hasPendingRental
                                ? () => _showConfirmation(state.rentalId)
                                : () async {
                                    context.read<RentalRequestCubit>().submit(
                                      _buildRentalDraft(),
                                    );
                                  },
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
                                      if (isConfirmed) ...[
                                        const Icon(
                                          Icons.assignment_outlined,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        isConfirmed
                                            ? 'ตรวจสอบสถานะ'
                                            : hasPendingRental
                                            ? 'ยืนยันการเช่า'
                                            : (_isCurrentUserOwner
                                                  ? 'รอผู้เช่ายืนยัน'
                                                  : (_bookingData
                                                                .originalMessageId !=
                                                            null
                                                        ? 'ยืนยันคำขอเช่า'
                                                        : 'ส่งคำขอเช่า')),
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
          unawaited(_showConfirmation(state.rentalId));
        }
        final errorMessage = state.errorMessage;
        if (!_isConfirmationSheetOpen &&
            errorMessage != null &&
            errorMessage.isNotEmpty) {
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
