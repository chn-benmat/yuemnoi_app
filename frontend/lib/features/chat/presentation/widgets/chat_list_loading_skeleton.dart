import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_shimmer.dart';

class ChatListLoadingSkeleton extends StatelessWidget {
  const ChatListLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      key: const ValueKey('chat-list-loading-skeleton'),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
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
      child: Row(
        children: [
          SkeletonBox(width: 60, height: 60, shape: BoxShape.circle),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 16, borderRadius: 8)),
                    SizedBox(width: 24),
                    SkeletonBox(width: 38, height: 10, borderRadius: 5),
                  ],
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.78,
                  child: SkeletonBox(height: 13, borderRadius: 7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
