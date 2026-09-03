import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../payment/domain/entities/payment.dart';
import '../../../payment/presentation/bloc/payment_cubit.dart';
import '../../../payment/presentation/bloc/payment_state.dart';
import '../../../wallet/presentation/bloc/wallet_cubit.dart';
import '../../../wallet/presentation/bloc/wallet_state.dart';
import '../../../wallet/presentation/widgets/wallet_insufficient_bottom_sheet.dart';
import '../../domain/entities/booking_request_model.dart';
import '../widgets/booking_location_card.dart';
import '../widgets/booking_payment_method_tile.dart';
import '../widgets/booking_price_summary_card.dart';
import '../widgets/booking_product_card.dart';
import '../widgets/booking_security_badge.dart';
import '../widgets/booking_time_range_picker.dart';

class BookingConfirmationPage extends StatefulWidget {
  const BookingConfirmationPage({super.key, this.bookingData});

  final BookingRequestData? bookingData;

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage>
    with WidgetsBindingObserver {
  late BookingRequestData _bookingData;
  BookingPaymentMethod _selectedPaymentMethod =
      BookingPaymentMethod.bankTransfer;
  bool _didShowSuccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        );

    _selectedPaymentMethod = _bookingData.paymentMethod;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PaymentCubit>().refresh();
    }
  }

  void _onPaymentMethodChanged(BookingPaymentMethod method) {
    setState(() {
      _selectedPaymentMethod = method;
      _bookingData = _bookingData.copyWith(paymentMethod: method);
    });
  }

  PaymentRentalDraft _buildRentalDraft() {
    final startAt = DateTime(
      _bookingData.startDate.year,
      _bookingData.startDate.month,
      _bookingData.startDate.day,
      _bookingData.startTime.hour,
      _bookingData.startTime.minute,
    );
    final endAt = _bookingData.rentalType == BookingRentalType.daily
        ? DateTime(
            _bookingData.endDate.year,
            _bookingData.endDate.month,
            _bookingData.endDate.day,
            _bookingData.startTime.hour,
            _bookingData.startTime.minute,
          )
        : DateTime(
            _bookingData.startDate.year,
            _bookingData.startDate.month,
            _bookingData.startDate.day,
            _bookingData.endTime.hour,
            _bookingData.endTime.minute,
          );

    return PaymentRentalDraft(
      itemId: _bookingData.item.id,
      startAt: startAt,
      endAt: endAt,
      rentalType: _bookingData.rentalType.name,
      pickupLocation: _bookingData.location,
    );
  }

  Future<void> _handlePayment() async {
    final draft = _buildRentalDraft();

    if (_selectedPaymentMethod == BookingPaymentMethod.wallet) {
      final walletBalance = context.read<WalletCubit>().state.balance;
      if (walletBalance < _bookingData.totalPrice) {
        WalletInsufficientBottomSheet.show(
          context,
          requiredAmount: _bookingData.totalPrice,
          currentBalance: walletBalance,
        );
        return;
      }

      final success = await context.read<PaymentCubit>().payWithWallet(draft);
      if (success && mounted) {
        final rentalId = context.read<PaymentCubit>().state.rentalId ?? 0;
        await context.read<WalletCubit>().payRental(
          rentalId: rentalId,
          amount: _bookingData.totalPrice,
        );
      }
      return;
    }

    final checkoutUrl = await context.read<PaymentCubit>().start(draft);
    if (!mounted || checkoutUrl == null) return;
    await _launchCheckout(checkoutUrl);
  }

  Future<void> _launchCheckout(Uri checkoutUrl) async {
    try {
      final launched = await launchUrl(
        checkoutUrl,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!launched) {
        final fallback = await launchUrl(
          checkoutUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        if (!fallback) context.read<PaymentCubit>().markLaunchFailed();
      }
    } catch (_) {
      final fallback = await launchUrl(
        checkoutUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!fallback) context.read<PaymentCubit>().markLaunchFailed();
    }
  }

  Future<void> _showPaymentSuccess({String providerName = 'Stripe'}) async {
    if (_didShowSuccess || !mounted) return;
    _didShowSuccess = true;
    final currencyFormatter = NumberFormat('#,##0.00', 'en_US');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ชำระเงินสำเร็จแล้ว!',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E2022),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ยอดชำระ ${currencyFormatter.format(_bookingData.totalPrice)} ฿ ยืนยันโดย $providerName',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF777A7C),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEBECEE)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'อุปกรณ์:',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: Color(0xFF777A7C),
                            ),
                          ),
                          Text(
                            _bookingData.item.title,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E2022),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'สถานที่นัดรับ:',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: Color(0xFF777A7C),
                            ),
                          ),
                          Text(
                            _bookingData.location,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E2022),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'สถานะ:',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              color: Color(0xFF777A7C),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'รอรับอุปกรณ์',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text(
                      'เสร็จสิ้น',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
    return BlocListener<PaymentCubit, PaymentState>(
      listener: (context, state) {
        if (state.flowStatus == PaymentFlowStatus.paid) {
          final provider = _selectedPaymentMethod == BookingPaymentMethod.wallet
              ? 'Yuemnoi Wallet'
              : 'Stripe';
          unawaited(_showPaymentSuccess(providerName: provider));
        }
        final errorMessage = state.errorMessage;
        if (errorMessage != null && errorMessage.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 24),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text(
            'ยืนยันการจอง',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. การ์ดสินค้า
                      BookingProductCard(item: _bookingData.item),
                      const SizedBox(height: 18),

                      // 2. วันที่เริ่มเช่า-สิ้นสุด
                      BookingTimeRangePicker(
                        sectionTitle: 'วันที่เริ่มเช่า-สิ้นสุด',
                        rentalType: _bookingData.rentalType,
                        startDate: _bookingData.startDate,
                        endDate: _bookingData.endDate,
                        startTime: _bookingData.startTime,
                        endTime: _bookingData.endTime,
                        isEditable: false,
                      ),
                      const SizedBox(height: 18),

                      // 3. สถานที่นัดพบ
                      BookingLocationCard(
                        location: _bookingData.location,
                        locationNote: _bookingData.locationNote,
                        isEditable: false,
                      ),
                      const SizedBox(height: 18),

                      // 4. สรุปราคา
                      BookingPriceSummaryCard(bookingData: _bookingData),
                      const SizedBox(height: 20),

                      // 5. วิธีการชำระเงิน
                      BlocBuilder<WalletCubit, WalletState>(
                        builder: (context, walletState) {
                          return BookingPaymentMethodSelector(
                            selectedMethod: _selectedPaymentMethod,
                            onChanged: _onPaymentMethodChanged,
                            walletBalance: walletState.balance,
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // 6. ตราประทับความปลอดภัย
                      const BookingSecurityBadge(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // 7. ปุ่ม "ชำระเงิน"
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: BlocBuilder<PaymentCubit, PaymentState>(
                    builder: (context, state) {
                      final isBusy =
                          state.flowStatus ==
                              PaymentFlowStatus.creatingCheckout ||
                          state.flowStatus == PaymentFlowStatus.checkingStatus;

                      String buttonLabel;
                      if (_selectedPaymentMethod == BookingPaymentMethod.wallet) {
                        buttonLabel = 'ชำระด้วย Yuemnoi Wallet';
                      } else if (state.flowStatus ==
                          PaymentFlowStatus.awaitingPayment) {
                        buttonLabel = 'เปิดหน้าชำระเงินอีกครั้ง';
                      } else {
                        buttonLabel = 'ชำระเงินผ่าน Stripe';
                      }

                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor: AppColors.primaryColor.withValues(
                            alpha: 0.35,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: isBusy
                            ? null
                            : (state.flowStatus ==
                                        PaymentFlowStatus.awaitingPayment &&
                                    _selectedPaymentMethod !=
                                        BookingPaymentMethod.wallet)
                                ? () {
                                    final checkoutUrl = state.checkoutUrl;
                                    if (checkoutUrl != null) {
                                      _launchCheckout(checkoutUrl);
                                    }
                                  }
                                : _handlePayment,
                        child: isBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                buttonLabel,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
