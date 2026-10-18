import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// คงรูปทรงระหว่างรอข้อมูล แล้วให้แพ็กเกจจัดการแสงและวงจรแอนิเมชัน
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Skeletonizer(
          effect: const ShimmerEffect(
            baseColor: Color(0xFFE3E5E8),
            highlightColor: Color(0xFFF7F8FA),
            duration: Duration(milliseconds: 1400),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// กล่องพื้นฐานสำหรับประกอบ skeleton ให้มีรูปทรงใกล้เคียงข้อมูลจริง
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 12,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Bone(
      width: width,
      height: height,
      shape: shape,
      borderRadius: shape == BoxShape.rectangle
          ? BorderRadius.circular(borderRadius)
          : null,
    );
  }
}
