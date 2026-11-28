import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

const _skeletonBaseColor = Color(0xFFE3E5E8);

/// ใส่แสงวิ่งให้ placeholder ระหว่างรอข้อมูล
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Shimmer.fromColors(
            baseColor: _skeletonBaseColor,
            highlightColor: const Color(0xFFF7F8FA),
            period: const Duration(milliseconds: 1400),
            direction: Directionality.of(context) == TextDirection.rtl
                ? ShimmerDirection.rtl
                : ShimmerDirection.ltr,
            child: child,
          ),
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
    // ไม่ระบุ width ให้กว้างเต็มพื้นที่ เหมือนข้อความจริงในคอลัมน์ที่ชิดซ้าย
    // LimitedBox กันกรณีความกว้างไม่จำกัด เช่นอยู่ใน Row โดยไม่มี Expanded
    return SizedBox(
      width: width,
      height: height,
      child: LimitedBox(
        maxWidth: 0,
        maxHeight: 0,
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _skeletonBaseColor,
              shape: shape,
              borderRadius: shape == BoxShape.rectangle
                  ? BorderRadius.circular(borderRadius)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
