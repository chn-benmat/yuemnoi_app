import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_shimmer.dart';

class ChatListLoadingSkeleton extends StatelessWidget {
  const ChatListLoadingSkeleton({super.key, this.count = 7});

  /// จำนวนรายการที่หน้านี้แสดงครั้งล่าสุด ให้ skeleton มีจำนวนเท่าข้อมูลจริง
  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      key: const ValueKey('chat-list-loading-skeleton'),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: Color(0xFFEBEBEF), indent: 84),
        itemBuilder: (context, index) => const _ChatListSkeletonTile(),
      ),
    );
  }
}

class _ChatListSkeletonTile extends StatelessWidget {
  const _ChatListSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SkeletonShimmer(
        child: Row(
          children: [
            SkeletonBox(width: 60, height: 60, shape: BoxShape.circle),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ความสูงบรรทัดเท่าชื่อ 16px และเวลา 12px ในการ์ดจริง
                  SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 0.55,
                            child: SkeletonBox(height: 16, borderRadius: 8),
                          ),
                        ),
                        SizedBox(width: 8),
                        SkeletonBox(width: 34, height: 11, borderRadius: 5),
                      ],
                    ),
                  ),
                  SizedBox(height: 4),
                  // ข้อความล่าสุด 14px บรรทัดเดียว
                  SizedBox(
                    height: 20,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: 0.78,
                        child: SkeletonBox(height: 13, borderRadius: 7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
