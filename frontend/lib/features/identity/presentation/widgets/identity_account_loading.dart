import 'package:flutter/material.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import 'identity_widgets.dart';

/// โครงหน้าข้อมูลบัตรขณะโหลด ใช้สัดส่วนเดียวกับ _photoTile และ _section
/// รูปคู่บัตร 4:3 รูปบัตร 1.586 ตามด้วยปุ่มเพิ่มรูป 48 และฟอร์ม 5 ช่อง
class IdentityAccountLoading extends StatelessWidget {
  const IdentityAccountLoading({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PhotoPanelBone(aspectRatio: 4 / 3),
        _PhotoPanelBone(aspectRatio: 1.586),
        _FormPanelBone(fieldCount: 5),
      ],
    ),
  );
}

/// หัวข้อ 17px และคำอธิบาย 12px สูงบรรทัด 1.6 แบบเดียวกับหน้าจริง
class _PanelHeaderBone extends StatelessWidget {
  const _PanelHeaderBone({required this.subtitleLines});

  final int subtitleLines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(
        height: 23,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 160, height: 17, borderRadius: 6),
        ),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < subtitleLines; i++)
        SizedBox(
          height: 19,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: i == subtitleLines - 1 ? 0.6 : 1,
              child: const SkeletonBox(height: 11, borderRadius: 4),
            ),
          ),
        ),
    ],
  );
}

class _PhotoPanelBone extends StatelessWidget {
  const _PhotoPanelBone({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: IdentityPanel(
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeaderBone(subtitleLines: 2),
            const SizedBox(height: 18),
            AspectRatio(
              aspectRatio: aspectRatio,
              child: const SkeletonBox(
                height: double.infinity,
                borderRadius: 16,
              ),
            ),
            const SizedBox(height: 16),
            const SkeletonBox(height: 48, borderRadius: 12),
          ],
        ),
      ),
    ),
  );
}

class _FormPanelBone extends StatelessWidget {
  const _FormPanelBone({required this.fieldCount});

  final int fieldCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: IdentityPanel(
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeaderBone(subtitleLines: 1),
            const SizedBox(height: 20),
            for (var i = 0; i < fieldCount; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              // ป้ายกำกับช่องกรอก และระยะห่าง 8 ก่อนช่อง
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SkeletonBox(width: 110, height: 14, borderRadius: 5),
              ),
              const SizedBox(height: 8),
              const SkeletonBox(height: 52),
            ],
          ],
        ),
      ),
    ),
  );
}
