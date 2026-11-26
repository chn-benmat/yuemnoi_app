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
        for (var i = 0; i < 2; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: IdentityPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 160, height: 20),
                  SizedBox(height: 10),
                  SkeletonBox(height: 14),
                  SizedBox(height: 20),
                  AspectRatio(
                    aspectRatio: 1.5,
                    child: SkeletonBox(height: 200),
                  ),
                ],
              ),
            ),
          ),
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
