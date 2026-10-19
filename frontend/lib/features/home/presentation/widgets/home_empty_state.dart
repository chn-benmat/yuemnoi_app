import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

/// วิดเจ็ตแสดงผลเมื่อไม่พบรายการอุปกรณ์จากการค้นหาหรือเลือกหมวดหมู่
class HomeEmptyState extends StatelessWidget {
  const HomeEmptyState({super.key, this.searchQuery = '', this.onReset});

  final String searchQuery;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: AppColors.primaryColor,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isNotEmpty
                  ? 'ไม่พบอุปกรณ์ที่ตรงกับ "$searchQuery"'
                  : 'ยังไม่มีอุปกรณ์ในหมวดหมู่นี้',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2E3236),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ลองค้นหาด้วยคำอื่น หรือเลือกหมวดหมู่อื่นดูนะ',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF7A7E82), fontSize: 13),
            ),
            if (onReset != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('ดูอุปกรณ์ทั้งหมด'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
