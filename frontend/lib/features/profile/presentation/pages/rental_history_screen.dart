import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class RentalHistoryScreen extends StatelessWidget {
  const RentalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy Data สำหรับประวัติการเช่า (สำเร็จแล้ว)
    final history = [
      _RentalHistoryItemData(
        title: 'Sony A7 IV',
        ownerName: 'คนที่ 3คนที่สาม',
        duration: 'เช่า 3 วัน',
        date: '12 ส.ค. 2026',
        status: 'เสร็จสิ้น',
        iconData: Icons.camera_alt_outlined,
      ),
      _RentalHistoryItemData(
        title: 'DJI Mavic Pro',
        ownerName: 'สกน จัสดี',
        duration: 'เช่า 1 วัน',
        date: '10 ส.ค. 2026',
        status: 'เสร็จสิ้น',
        iconData: Icons.flight_takeoff_outlined,
      ),
      _RentalHistoryItemData(
        title: 'MacBook Pro M2',
        ownerName: 'ซาร่า เวกัส',
        duration: 'เช่า 5 วัน',
        date: '5 ส.ค. 2026',
        status: 'เสร็จสิ้น',
        iconData: Icons.laptop_mac_outlined,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ประวัติการเช่า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        itemCount: history.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = history[index];
          return _RentalHistoryCard(item: item);
        },
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _RentalHistoryItemData {
  final String title;
  final String ownerName;
  final String duration;
  final String date;
  final String status;
  final IconData iconData;

  _RentalHistoryItemData({
    required this.title,
    required this.ownerName,
    required this.duration,
    required this.date,
    required this.status,
    required this.iconData,
  });
}

// ─── Card Widget ──────────────────────────────────────────────────────────────

class _RentalHistoryCard extends StatelessWidget {
  final _RentalHistoryItemData item;

  const _RentalHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon Box ──
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              item.iconData,
              color: AppColors.primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          // ── Details ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'เช่าจาก: ${item.ownerName}',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: AppColors.hintTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.date} • ${item.duration}',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: AppColors.hintTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Status ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.status,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
