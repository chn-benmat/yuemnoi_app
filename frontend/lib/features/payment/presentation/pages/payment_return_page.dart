import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../bloc/payment_cubit.dart';
import '../bloc/payment_state.dart';

class PaymentReturnPage extends StatefulWidget {
  const PaymentReturnPage({super.key, required this.rentalId});

  final int rentalId;

  @override
  State<PaymentReturnPage> createState() => _PaymentReturnPageState();
}

class _PaymentReturnPageState extends State<PaymentReturnPage> {
  @override
  void initState() {
    super.initState();
    context.read<PaymentCubit>().refresh(rentalId: widget.rentalId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สถานะการชำระเงิน'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: BlocBuilder<PaymentCubit, PaymentState>(
          builder: (context, state) {
            final isLoading =
                state.flowStatus == PaymentFlowStatus.initial ||
                state.flowStatus == PaymentFlowStatus.checkingStatus;
            final isPaid = state.flowStatus == PaymentFlowStatus.paid;
            final title = isLoading
                ? 'กำลังตรวจสอบกับเซิร์ฟเวอร์'
                : isPaid
                ? 'ชำระเงินสำเร็จ'
                : state.flowStatus == PaymentFlowStatus.awaitingPayment
                ? 'กำลังรอการยืนยันจาก Stripe'
                : 'ยังยืนยันการชำระเงินไม่ได้';
            final icon = isLoading
                ? null
                : isPaid
                ? Icons.check_circle_rounded
                : Icons.schedule_rounded;

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading)
                      const CircularProgressIndicator()
                    else
                      Icon(
                        icon,
                        size: 72,
                        color: isPaid
                            ? const Color(0xFF10B981)
                            : AppColors.primaryColor,
                      ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: Color(0xFF777A7C),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (!isPaid)
                      FilledButton(
                        onPressed: isLoading
                            ? null
                            : () => context.read<PaymentCubit>().refresh(
                                rentalId: widget.rentalId,
                              ),
                        child: const Text('ตรวจสอบอีกครั้ง'),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => AppRoutes.goToHome(context),
                      child: const Text('กลับหน้าหลัก'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
