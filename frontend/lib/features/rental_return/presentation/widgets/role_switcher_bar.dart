import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';
import '../cubit/rental_return_cubit.dart';
import '../cubit/rental_return_state.dart';

class RoleSwitcherBar extends StatelessWidget {
  const RoleSwitcherBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RentalReturnCubit, RentalReturnState>(
      builder: (context, state) {
        final cubit = context.read<RentalReturnCubit>();
        final isRenter = state.isRenter;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // แท็บผู้เช่า
                  Expanded(
                    child: GestureDetector(
                      onTap: () => cubit.switchRole(RentalUserRole.renter),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isRenter
                              ? AppColors.primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 18,
                              color: isRenter ? Colors.white : AppColors.fieldIconColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'มุมมองผู้เช่า (Customer)',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                fontWeight: isRenter ? FontWeight.bold : FontWeight.w500,
                                color: isRenter ? Colors.white : AppColors.labelColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // แท็บผู้ให้เช่า
                  Expanded(
                    child: GestureDetector(
                      onTap: () => cubit.switchRole(RentalUserRole.lender),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isRenter
                              ? const Color(0xFF10B981)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.storefront_outlined,
                              size: 18,
                              color: !isRenter ? Colors.white : AppColors.fieldIconColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'มุมมองร้านค้า (Lender)',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                fontWeight: !isRenter ? FontWeight.bold : FontWeight.w500,
                                color: !isRenter ? Colors.white : AppColors.labelColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // แถบปุ่มช่วยเหลือสำหรับทดสอบ Scenario
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: cubit.triggerUrgentAlarm,
                      icon: const Icon(Icons.notifications_active_outlined, size: 16, color: Color(0xFFF59E0B)),
                      label: const Text(
                        'ทดสอบปลุกเตือนภัย',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: cubit.resetDemo,
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.fieldIconColor),
                      label: const Text(
                        'รีเซ็ตสถานะ',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          color: AppColors.labelColor,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
