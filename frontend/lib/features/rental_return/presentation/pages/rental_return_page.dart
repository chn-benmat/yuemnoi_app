import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/repositories/rental_return_repository_impl.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';
import '../widgets/lender_inspection_view.dart';
import '../widgets/live_camera_capture_sheet.dart';
import '../widgets/merchant_qr_dialog.dart';
import '../widgets/rental_time_card.dart';
import '../widgets/return_completed_dialog.dart';
import '../widgets/renter_qr_scanner_sheet.dart';
import '../../domain/repositories/rental_return_repository.dart';
import '../widgets/urgent_return_alarm_dialog.dart';

class RentalReturnPage extends StatelessWidget {
  final int? rentalId;
  final bool? isLender;
  final RentalReturnRepository? repository;

  const RentalReturnPage({
    super.key,
    this.rentalId,
    this.isLender,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RentalReturnCubit(
        repository: repository ?? RentalReturnRepositoryImpl(),
      )..loadSession(rentalId: rentalId, isLender: isLender),
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
  Timer? _refreshTimer;
  bool _qrOpen = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<RentalReturnCubit>().refreshSession();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

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
    _qrOpen = true;
    MerchantQrDialog.show(
      context: context,
      qrData: state.session.merchantQrToken!,
      otp: state.session.merchantOtp,
      expiryTime: state.merchantQrExpiry,
      onRefresh: () async {
        final cubit = context.read<RentalReturnCubit>();
        await cubit.confirmLenderInspection();
        if (context.mounted && cubit.state.errorMessage == null) {
          _openMerchantQrModal(context, cubit.state);
        }
      },
    ).whenComplete(() => _qrOpen = false);
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
          showAppPopup(
            context,
            content: Text(
              state.errorMessage!,
              style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
            ),
          );
        }

        if (state.isAlarmActive && !_didShowAlarm && state.isRenter) {
          _didShowAlarm = true;
          UrgentReturnAlarmDialog.show(
            context: context,
            session: state.session,
            onProceedToVerification: () {
              context
                  .read<RentalReturnCubit>()
                  .dismissAlarmAndStartVerification();
            },
          );
        }

        if (state.session.step == RentalReturnStep.completed) {
          _showCompletion(state);
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
        if (state.status == RentalReturnStatus.error) {
          return Scaffold(
            appBar: AppBar(title: const Text('การคืนอุปกรณ์')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(state.errorMessage ?? 'โหลดรายการคืนไม่สำเร็จ'),
              ),
            ),
          );
        }

        if (state.status == RentalReturnStatus.loaded &&
            state.session.step == RentalReturnStep.completed &&
            !_didShowSuccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showCompletion(state);
          });
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
              child: Container(color: const Color(0xFFF1F5F9), height: 1),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ข้อมูลอุปกรณ์และกำหนดเวลาคืน (อ่านง่าย)
                RentalTimeCard(session: session),

                _ReturnProgress(session: session),

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
                              onPressed:
                                  state.isSubmitting ||
                                      session.step !=
                                          RentalReturnStep.merchantQrReady
                                  ? null
                                  : () => _openQrScanner(context),
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
                                  ? null
                                  : () => _openMerchantQrModal(context, state),
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                session.merchantQrToken == null
                                    ? 'ยืนยันการตรวจสภาพด้านบนก่อน'
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

  void _showCompletion(RentalReturnState state) {
    if (_didShowSuccess) return;
    _didShowSuccess = true;
    if (!state.isRenter && _qrOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      _qrOpen = false;
    }
    unawaited(
      ReturnCompletedDialog.show(
        context: context,
        session: state.session,
        onDismiss: _leaveReturnFlow,
      ),
    );
  }

  void _leaveReturnFlow() {
    _refreshTimer?.cancel();
    if (mounted) AppRoutes.goToHomeAfterRental(context);
  }
}

class _ReturnProgress extends StatelessWidget {
  const _ReturnProgress({required this.session});
  final RentalReturnSession session;

  @override
  Widget build(BuildContext context) {
    final step = switch (session.step) {
      RentalReturnStep.awaitingHandover ||
      RentalReturnStep.lenderInspecting => 1,
      RentalReturnStep.merchantQrReady || RentalReturnStep.completed => 2,
      _ => 0,
    };
    const labels = ['ตรวจสภาพ', 'ตรวจรับคืน', 'ยืนยันคืน'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: i <= step
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == step
                        ? AppColors.primaryColor
                        : i < step
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: i < step
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        )
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i == step
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                    color: i == step
                        ? AppColors.primaryColor
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
