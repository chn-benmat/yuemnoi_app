import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_popup.dart';
import '../../../profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import '../../data/repositories/rental_return_repository_impl.dart';
import '../../domain/entities/rental_return_session.dart';
import '../../domain/repositories/rental_return_repository.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';
import '../widgets/lender_inspection_view.dart';
import '../widgets/rental_time_card.dart';
import '../widgets/return_completed_dialog.dart';
import '../widgets/return_evidence_gallery.dart';
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
  int? _checkedRentalId;
  Timer? _refreshTimer;
  DialogRoute<void>? _alarmRoute;

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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RentalReturnCubit, RentalReturnState>(
      listenWhen: (prev, current) =>
          prev.isAlarmActive != current.isAlarmActive ||
          prev.session.step != current.session.step ||
          prev.errorMessage != current.errorMessage,
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

        if (state.session.step == RentalReturnStep.completed) {
          unawaited(_showCompletion(state));
        } else if (state.isAlarmActive && !_didShowAlarm && state.isRenter) {
          _didShowAlarm = true;
          final navigator = Navigator.of(context, rootNavigator: true);
          final alarmRoute = UrgentReturnAlarmDialog.createRoute(
            context: context,
            session: state.session,
            onDismiss: context.read<RentalReturnCubit>().dismissAlarm,
          );
          _alarmRoute = alarmRoute;
          unawaited(
            navigator.push(alarmRoute).whenComplete(() {
              _alarmRoute = null;
            }),
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
        if (state.status == RentalReturnStatus.error) {
          return Scaffold(
            appBar: AppBar(title: const Text('คืนสินค้า')),
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
            if (mounted) unawaited(_showCompletion(state));
          });
        }
        final session = state.session;
        final isCompleted = session.step == RentalReturnStep.completed;
        final returnPoint = isCompleted ? null : session.returnPoint;
        final location = session.pickupLocation.trim();

        return RentalTrackingMapPage(
          key: ValueKey((session.rentalId, returnPoint, location)),
          itemTitle: session.itemName,
          itemImageUrl: session.itemImageUrl,
          pickupLocation: location.isEmpty
              ? 'ยังไม่มีข้อมูลจุดคืนสินค้า'
              : location,
          pickupNote: session.returnPoint?.note,
          periodText: isCompleted
              ? 'คืนสินค้าเรียบร้อยแล้ว'
              : 'กำหนดคืน ${session.endAtFormatted}',
          returnPoint: returnPoint,
          returnDetails: isCompleted
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    RentalTimeCard(session: session),
                    if (session.photos.any((photo) => photo.hasPhoto))
                      ReturnEvidenceGallery(photos: session.photos),
                    if (state.isRenter)
                      _RenterReturnStatus(
                        awaitingConfirmation:
                            session.step == RentalReturnStep.lenderInspecting,
                      )
                    else
                      LenderInspectionView(
                        isChecked: _checkedRentalId == session.rentalId,
                        isSubmitting: state.isSubmitting,
                        onChecked: (checked) => setState(() {
                          _checkedRentalId = checked ? session.rentalId : null;
                        }),
                        onConfirm: context
                            .read<RentalReturnCubit>()
                            .confirmMerchantReceipt,
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _showCompletion(RentalReturnState state) async {
    if (_didShowSuccess) return;
    _didShowSuccess = true;
    _refreshTimer?.cancel();

    final alarmRoute = _alarmRoute;
    if (alarmRoute != null && alarmRoute.isActive) {
      alarmRoute.navigator?.removeRoute(alarmRoute);
    }
    if (state.isAlarmActive) {
      unawaited(context.read<RentalReturnCubit>().dismissAlarm());
    }

    final session = state.session;
    if (state.isRenter && session.itemId != null) {
      await AppRoutes.openReview(
        context,
        bookingId: session.rentalId,
        itemId: session.itemId,
        itemName: session.itemName,
        ownerName: session.lenderName,
        ownerId: session.lenderId,
        itemImageUrl: session.itemImageUrl,
      );
      _leaveReturnFlow();
    } else {
      await ReturnCompletedDialog.show(
        context: context,
        session: session,
        onDismiss: _leaveReturnFlow,
      );
    }
  }

  void _leaveReturnFlow() {
    if (mounted) AppRoutes.goToHomeAfterRental(context);
  }
}

class _RenterReturnStatus extends StatelessWidget {
  const _RenterReturnStatus({required this.awaitingConfirmation});

  final bool awaitingConfirmation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ส่งคืนสินค้า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  awaitingConfirmation
                      ? Icons.hourglass_top_rounded
                      : Icons.place_outlined,
                  size: 20,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        awaitingConfirmation
                            ? 'รอร้านค้ายืนยันรับสินค้าคืน'
                            : 'นำสินค้าไปส่งที่จุดคืนตามนัด',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'ร้านค้าจะตรวจสภาพและยืนยันเมื่อได้รับสินค้า',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
