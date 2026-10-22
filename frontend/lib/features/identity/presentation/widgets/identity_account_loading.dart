import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import 'identity_widgets.dart';

class IdentityAccountLoading extends StatelessWidget {
  const IdentityAccountLoading({super.key});

  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IdentityPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 16),
              SizedBox(height: 18),
              SkeletonBox(width: 240, height: 24),
              SizedBox(height: 12),
              SkeletonBox(height: 14),
              SizedBox(height: 8),
              SkeletonBox(width: 200, height: 14),
            ],
          ),
        ),
        for (var i = 0; i < 2; i++) ...[
          const SizedBox(height: 16),
          const IdentityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 160, height: 20),
                SizedBox(height: 10),
                SkeletonBox(height: 14),
                SizedBox(height: 20),
                AspectRatio(aspectRatio: 1.5, child: SkeletonBox(height: 200)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        IdentityPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 170, height: 20),
              for (var i = 0; i < 4; i++) ...[
                const SizedBox(height: 24),
                const SkeletonBox(width: 100, height: 14),
                const SizedBox(height: 10),
                const SkeletonBox(height: 52),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
