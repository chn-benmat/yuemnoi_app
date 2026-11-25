import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import '../../data/repositories/rental_return_repository_impl.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';
import '../widgets/lender_inspection_view.dart';
import '../widgets/rental_time_card.dart';
import '../widgets/return_completed_dialog.dart';
import '../widgets/return_evidence_gallery.dart';
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
            if (mounted) unawaited(_showCompletion(state));
          });
        }
        final session = state.session;
        final isRenter = state.isRenter;
        final isCompleted = session.step == RentalReturnStep.completed;
        final returnPoint = session.returnPoint;

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
          body: Column(
            children: [
              if (!isCompleted && returnPoint != null)
                Expanded(
                  flex: 5,
                  child: RentalTrackingMapPage(
                    key: ValueKey(returnPoint),
                    returnPoint: returnPoint,
                  ),
                ),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RentalTimeCard(session: session),
                      _ReturnProgress(session: session),
                      if (!isCompleted && isRenter) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(24, 12, 24, 12),
                          child: Text(
                            'รอร้านค้ายืนยันรับอุปกรณ์คืน',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: Color(0xFF475569),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (session.photos.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                            child: ReturnEvidenceGallery(
                              photos: session.photos,
                            ),
                          ),
                      ] else if (!isCompleted)
                        const LenderInspectionView(),
                    ],
                  ),
                ),
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

class _ReturnProgress extends StatelessWidget {
  const _ReturnProgress({required this.session});
  final RentalReturnSession session;

  @override
  Widget build(BuildContext context) {
    final step = switch (session.step) {
      RentalReturnStep.completed => 1,
      _ => 0,
    };
    const labels = ['ตรวจรับคืน', 'ยืนยันคืน'];
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
