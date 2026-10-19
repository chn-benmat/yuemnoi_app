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
      buildWhen: (prev, current) => prev.isRenter != current.isRenter,
      builder: (context, state) {
        final cubit = context.read<RentalReturnCubit>();
        final isRenter = state.isRenter;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFECEEF2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // แท็บผู้เช่า
              Expanded(
                child: GestureDetector(
                  onTap: () => cubit.switchRole(RentalUserRole.renter),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isRenter ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isRenter
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: isRenter
                              ? AppColors.primaryColor
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ผู้เช่า (Customer)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12.5,
                            fontWeight: isRenter
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isRenter
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // แท็บร้านค้า
              Expanded(
                child: GestureDetector(
                  onTap: () => cubit.switchRole(RentalUserRole.lender),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: !isRenter ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: !isRenter
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 16,
                          color: !isRenter
                              ? const Color(0xFF10B981)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ร้านค้า (Lender)',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12.5,
                            fontWeight: !isRenter
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: !isRenter
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
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
}
