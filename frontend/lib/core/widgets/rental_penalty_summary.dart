import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_penalty_terms.dart';

class RentalPenaltySummary extends StatelessWidget {
  const RentalPenaltySummary({super.key, required this.terms});

  final RentalPenaltyTerms terms;

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final format = NumberFormat.decimalPattern('th');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 5,
        children: [
          Text('ค่าปรับตามเงื่อนไขการเช่า', style: theme.textTheme.titleSmall),
          if (terms.damageFee > 0)
            Text('ชำรุด ${format.format(terms.damageFee)} บาท / ครั้ง'),
          if (terms.lateReturnFee > 0)
            Text(
              'คืนเกินกำหนด ${format.format(terms.lateReturnFee)} บาท / ครั้ง',
            ),
          if (terms.damageTerms.isNotEmpty)
            Text('เงื่อนไขกรณีชำรุด\n${terms.damageTerms}'),
        ],
      ),
    );
  }
}
