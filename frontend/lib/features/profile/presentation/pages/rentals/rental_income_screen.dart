import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../widgets/rentals/rental_income_widgets.dart';

class RentalIncomeScreen extends StatelessWidget {
  const RentalIncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy Data สำหรับรายได้และประวัติการปล่อยเช่า
    const totalIncome = 12500.0;
    const pendingIncome = 1200.0;

    final history = [
      RentalIncomeTransaction(
        itemName: 'Sony A7 IV',
        date: '12 ส.ค. 2026',
        duration: 'เช่า 3 วัน',
        amount: 2400,
        status: 'เสร็จสิ้น',
      ),
      RentalIncomeTransaction(
        itemName: 'DJI Mavic Pro',
        date: '10 ส.ค. 2026',
        duration: 'เช่า 1 วัน',
        amount: 800,
        status: 'เสร็จสิ้น',
      ),
      RentalIncomeTransaction(
        itemName: 'MacBook Pro M2',
        date: '5 ส.ค. 2026',
        duration: 'เช่า 5 วัน',
        amount: 4500,
        status: 'เสร็จสิ้น',
      ),
      RentalIncomeTransaction(
        itemName: 'Sony A7 IV',
        date: '1 ส.ค. 2026',
        duration: 'เช่า 2 วัน',
        amount: 1600,
        status: 'เสร็จสิ้น',
      ),
      RentalIncomeTransaction(
        itemName: 'เลนส์ FE 50mm f/1.8',
        date: '28 ก.ค. 2026',
        duration: 'เช่า 4 วัน',
        amount: 1200,
        status: 'เสร็จสิ้น',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'รายได้การปล่อยเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ── Dashboard Overview ──
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.primaryColor,
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 30,
                top: 10,
              ),
              child: Column(
                children: [
                  const Text(
                    'รายได้รวมทั้งหมด',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '฿ ${totalIncome.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: RentalIncomeStatCard(
                          title: 'รายได้ที่รอรับ',
                          value: '฿ ${pendingIncome.toStringAsFixed(0)}',
                          icon: Icons.pending_actions_rounded,
                          color: const Color(0xFFFFB74D),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: RentalIncomeStatCard(
                          title: 'ปล่อยเช่าสำเร็จ',
                          value: '${history.length} รายการ',
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF81C784),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── History List ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ประวัติการปล่อยเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryColor,
                      textStyle: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('ทั้งหมด'),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final tx = history[index];
                return RentalIncomeTransactionItem(tx: tx);
              }, childCount: history.length),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}
