import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_shimmer.dart';

class RentalNotificationLoadingSkeleton extends StatelessWidget {
  const RentalNotificationLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [_RentalCardSkeleton(), _RentalCardSkeleton()],
      ),
    );
  }
}

class SystemNotificationLoadingSkeleton extends StatelessWidget {
  const SystemNotificationLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_SystemCardSkeleton(), _SystemCardSkeleton()],
      ),
    );
  }
}

class _RentalCardSkeleton extends StatelessWidget {
  const _RentalCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _NotificationSkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.65,
                  child: SkeletonBox(height: 12, borderRadius: 4),
                ),
              ),
              SizedBox(width: 12),
              SkeletonBox(width: 72, height: 22, borderRadius: 4),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 58, height: 58, borderRadius: 8),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 15, borderRadius: 4),
                    SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.8,
                      child: SkeletonBox(height: 12, borderRadius: 4),
                    ),
                    SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: SkeletonBox(height: 11, borderRadius: 4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          SkeletonBox(height: 32, borderRadius: 6),
        ],
      ),
    );
  }
}

class _SystemCardSkeleton extends StatelessWidget {
  const _SystemCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _NotificationSkeletonCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 36, height: 36, borderRadius: 8),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.65,
                  child: SkeletonBox(height: 11, borderRadius: 4),
                ),
                SizedBox(height: 8),
                SkeletonBox(height: 14, borderRadius: 4),
                SizedBox(height: 8),
                SkeletonBox(height: 12, borderRadius: 4),
                SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.85,
                  child: SkeletonBox(height: 12, borderRadius: 4),
                ),
                SizedBox(height: 10),
                SkeletonBox(width: 84, height: 12, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationSkeletonCard extends StatelessWidget {
  const _NotificationSkeletonCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}
