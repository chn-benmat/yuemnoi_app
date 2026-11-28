import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/rental_income.dart';

class RentalIncomeStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const RentalIncomeStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// skeleton ของการ์ดประวัติการรับเงิน ใช้กรอบ ระยะ และขนาดเดียวกับ
/// [RentalIncomeTransactionItem] เพื่อไม่ให้หน้ากระโดดตอนข้อมูลจริงมาแทน
class RentalIncomeTransactionSkeleton extends StatelessWidget {
  const RentalIncomeTransactionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // พื้นการ์ดสีขาวอยู่นอก shimmer เพราะ shimmer จะทาสีทับทุกพิกเซลที่ทึบ
    return Container(
      key: const ValueKey('rental-income-transaction-skeleton'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const SkeletonShimmer(
        child: Row(
          children: [
            // ไอคอนเงินขนาด 48 มุมโค้ง 12
            SkeletonBox(width: 48, height: 48, borderRadius: 12),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ชื่ออุปกรณ์ 15px ตัวหนา
                  SizedBox(
                    height: 22,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        child: SkeletonBox(height: 15, borderRadius: 7),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  // วันเวลา dd/MM/yyyy HH:mm 13px
                  SizedBox(
                    height: 19,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SkeletonBox(
                        width: 110,
                        height: 12,
                        borderRadius: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ยอดเงิน +฿xxx.xx
                SizedBox(
                  height: 22,
                  child: Center(
                    child: SkeletonBox(width: 72, height: 15, borderRadius: 7),
                  ),
                ),
                SizedBox(height: 4),
                // ป้ายช่องทางรับเงิน
                SkeletonBox(width: 56, height: 22, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RentalIncomeTransactionItem extends StatelessWidget {
  final RentalIncomeEntry tx;

  const RentalIncomeTransactionItem({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(tx.confirmedAt.toLocal());
    final method = switch (tx.paymentMethod) {
      'cash' => 'เงินสด',
      'promptpay' => 'PromptPay',
      _ => 'ยืนยันรับเงินแล้ว',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.monetization_on_outlined,
              color: AppColors.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.itemName.isEmpty ? 'อุปกรณ์ให้เช่า' : tx.itemName,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: AppColors.hintTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+฿${(tx.amountSatang / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF43A047),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  method,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
