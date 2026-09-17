import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';

class RentalIncomeScreen extends StatelessWidget {
  const RentalIncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy Data สำหรับรายได้และประวัติการปล่อยเช่า
    const totalIncome = 12500.0;
    const pendingIncome = 1200.0;
    
    final history = [
      _IncomeTransaction(
        itemName: 'Sony A7 IV',
        date: '12 ส.ค. 2026',
        duration: 'เช่า 3 วัน',
        amount: 2400,
        status: 'เสร็จสิ้น',
      ),
      _IncomeTransaction(
        itemName: 'DJI Mavic Pro',
        date: '10 ส.ค. 2026',
        duration: 'เช่า 1 วัน',
        amount: 800,
        status: 'เสร็จสิ้น',
      ),
      _IncomeTransaction(
        itemName: 'MacBook Pro M2',
        date: '5 ส.ค. 2026',
        duration: 'เช่า 5 วัน',
        amount: 4500,
        status: 'เสร็จสิ้น',
      ),
      _IncomeTransaction(
        itemName: 'Sony A7 IV',
        date: '1 ส.ค. 2026',
        duration: 'เช่า 2 วัน',
        amount: 1600,
        status: 'เสร็จสิ้น',
      ),
      _IncomeTransaction(
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
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 30, top: 10),
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
                        child: _StatCard(
                          title: 'รายได้ที่รอรับ',
                          value: '฿ ${pendingIncome.toStringAsFixed(0)}',
                          icon: Icons.pending_actions_rounded,
                          color: const Color(0xFFFFB74D),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
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
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tx = history[index];
                  return _TransactionItem(tx: tx);
                },
                childCount: history.length,
              ),
            ),
          ),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _IncomeTransaction {
  final String itemName;
  final String date;
  final String duration;
  final double amount;
  final String status;

  _IncomeTransaction({
    required this.itemName,
    required this.date,
    required this.duration,
    required this.amount,
    required this.status,
  });
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
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

class _TransactionItem extends StatelessWidget {
  final _IncomeTransaction tx;

  const _TransactionItem({required this.tx});

  @override
  Widget build(BuildContext context) {
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
                  tx.itemName,
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
                  '${tx.date} • ${tx.duration}',
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
                '+฿${tx.amount.toStringAsFixed(0)}',
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
                  tx.status,
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
