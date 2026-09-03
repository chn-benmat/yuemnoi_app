import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingPaymentMethodSelector extends StatelessWidget {
  const BookingPaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onChanged,
    this.walletBalance,
  });

  final BookingPaymentMethod selectedMethod;
  final ValueChanged<BookingPaymentMethod> onChanged;
  final double? walletBalance;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat('#,##0.00', 'en_US');
    final formattedWallet = walletBalance != null
        ? ' (คงเหลือ ${currencyFormatter.format(walletBalance)} ฿)'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'วิธีการชำระเงิน',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 10),

        // Method 1: บัตรเครดิต/เดบิต (Stripe)
        _PaymentOptionTile(
          title: 'บัตรเครดิต / เดบิต',
          subtitle: 'ชำระปลอดภัยผ่าน Stripe Checkout',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFB154FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.credit_card_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.bankTransfer,
          onTap: () => onChanged(BookingPaymentMethod.bankTransfer),
        ),
        const SizedBox(height: 12),

        // Method 2: PromptPay QR (Stripe)
        _PaymentOptionTile(
          title: 'PromptPay QR',
          subtitle: 'สแกน QR Code ผ่านแอปธนาคาร',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFE8EAED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Color(0xFF1E2022),
              size: 24,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.promptPay,
          onTap: () => onChanged(BookingPaymentMethod.promptPay),
        ),
        const SizedBox(height: 12),

        // Method 3: กระเป๋าเงิน Yuemnoi (Wallet)
        _PaymentOptionTile(
          title: 'กระเป๋าเงิน Yuemnoi',
          subtitle: 'หักจากเงินในบัญชี$formattedWallet',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.primaryColor,
              size: 22,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.wallet,
          onTap: () => onChanged(BookingPaymentMethod.wallet),
        ),
        const SizedBox(height: 8),
        const Text(
          'คุณสามารถตรวจสอบยอดและวิธีชำระเงินก่อนยืนยันรายการได้',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            color: Color(0xFF777A7C),
          ),
        ),
      ],
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.title,
    this.subtitle,
    required this.iconWidget,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget iconWidget;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? AppColors.primaryColor : const Color(0xFFF1F3F5),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E2022),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF777A7C),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Custom Radio Button
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFFB5B7B9),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
