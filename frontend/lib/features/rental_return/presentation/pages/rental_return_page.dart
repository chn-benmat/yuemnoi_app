import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/repositories/rental_return_repository_impl.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';
import '../widgets/lender_inspection_view.dart';
import '../widgets/live_camera_capture_sheet.dart';
import '../widgets/merchant_qr_dialog.dart';
import '../widgets/rental_time_card.dart';
import '../widgets/renter_qr_scanner_sheet.dart';
import '../widgets/return_completed_dialog.dart';
import '../widgets/role_switcher_bar.dart';
import '../widgets/urgent_return_alarm_dialog.dart';

class RentalReturnPage extends StatelessWidget {
  final int? rentalId;

  const RentalReturnPage({
    super.key,
    this.rentalId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RentalReturnCubit(
        repository: RentalReturnRepositoryImpl(),
      )..loadSession(rentalId),
      child: const _RentalReturnView(),
    );
  }
}

class _RentalReturnView extends StatefulWidget {
  const _RentalReturnView();

  @override
  State<_RentalReturnView> createState() => _RentalReturnViewState();
}

class _RentalReturnViewState extends State<_RentalReturnView> {
  bool _didShowAlarm = false;
  bool _didShowSuccess = false;

  void _openQrScanner(BuildContext context) {
    RenterQrScannerSheet.show(
      context: context,
      onCodeScanned: (code) {
        context.read<RentalReturnCubit>().completeReturnWithQr(code);
      },
    );
  }

  void _openMerchantQrModal(BuildContext context, RentalReturnState state) {
    if (state.session.merchantQrToken == null) return;
    MerchantQrDialog.show(
      context: context,
      qrData: state.session.merchantQrToken!,
      otp: state.session.merchantOtp,
      expiryTime: state.merchantQrExpiry,
      onRefresh: () => context.read<RentalReturnCubit>().confirmLenderInspection(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RentalReturnCubit, RentalReturnState>(
      listenWhen: (prev, current) =>
          prev.isAlarmActive != current.isAlarmActive ||
          prev.session.step != current.session.step ||
          prev.errorMessage != current.errorMessage ||
          prev.successMessage != current.successMessage,
      listener: (context, state) {
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.errorMessage!,
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        if (state.successMessage != null && state.successMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.successMessage!,
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        if (state.isAlarmActive && !_didShowAlarm && state.isRenter) {
          _didShowAlarm = true;
          UrgentReturnAlarmDialog.show(
            context: context,
            session: state.session,
            onProceedToVerification: () {
              context.read<RentalReturnCubit>().dismissAlarmAndStartVerification();
            },
          );
        }

        if (state.session.step == RentalReturnStep.completed && !_didShowSuccess) {
          _didShowSuccess = true;
          ReturnCompletedDialog.show(
            context: context,
            session: state.session,
            onDismiss: () {
              Navigator.of(context).pop();
            },
          );
        }
      },
      builder: (context, state) {
        if (state.status == RentalReturnStatus.loading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            ),
          );
        }

        final session = state.session;
        final isRenter = state.isRenter;
        final isCompleted = session.step == RentalReturnStep.completed;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1E293B),
            elevation: 0,
            leading: const BackButton(color: Color(0xFF1E293B)),
            centerTitle: true,
            title: Text(
              isRenter ? 'การคืนอุปกรณ์' : 'รับมอบอุปกรณ์คืน',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Color(0xFF0F172A),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                color: const Color(0xFFF1F5F9),
                height: 1,
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFF64748B),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  final cubit = context.read<RentalReturnCubit>();
                  if (value == 'alarm') {
                    cubit.triggerUrgentAlarm();
                  } else if (value == 'reset') {
                    cubit.resetDemo();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'alarm',
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                          color: Color(0xFFD97706),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'ทดสอบปลุกเตือนภัย',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: Row(
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'รีเซ็ตสถานะ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // สวิตช์สลับบทบาทแบบมินิมอล
                const RoleSwitcherBar(),

                // ข้อมูลอุปกรณ์และกำหนดเวลาคืน (อ่านง่าย)
                RentalTimeCard(session: session),

                // มุมมองตามบทบาท
                if (isRenter) ...[
                  if (!isCompleted) const LiveCameraCaptureSheet(),
                ] else ...[
                  if (!isCompleted) const LenderInspectionView(),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),

          // ปุ่ม Action ลอยด้านล่าง
          bottomSheet: isCompleted
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    border: const Border(
                      top: BorderSide(color: Color(0xFFF1F5F9)),
                    ),
                  ),
                  child: SafeArea(
                    child: isRenter
                        ? SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () => _openQrScanner(context),
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: const Text(
                                'สแกน QR Code ร้านค้าเพื่อจบการคืน',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: session.merchantQrToken == null
                                  ? () => context
                                      .read<RentalReturnCubit>()
                                      .confirmLenderInspection()
                                  : () => _openMerchantQrModal(context, state),
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                session.merchantQrToken == null
                                    ? 'ตรวจสอบเครื่องแล้ว & แสดง QR'
                                    : 'เปิดแสดง QR Code ให้ลูกค้าสแกน',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
        );
      },
    );
  }
}
