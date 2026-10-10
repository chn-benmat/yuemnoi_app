import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

class IdentityColors {
  IdentityColors._();
  static const primary = AppColors.primaryColor;
  static const ink = Color(0xFF241B32);
  static const muted = Color(0xFF746C80);
  static const canvas = Color(0xFFFAF8FD);
  static const line = Color(0xFFEAE4F1);
  static const tint = Color(0xFFF1E7FC);
  static const success = Color(0xFF18734E);
  static const warning = Color(0xFF926012);
}

class IdentityHeading extends StatelessWidget {
  const IdentityHeading(this.title, this.subtitle, {super.key, this.eyebrow});
  final String title, subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!,
          style: const TextStyle(
            color: IdentityColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        title,
        style: const TextStyle(
          fontSize: 26,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: IdentityColors.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          height: 1.7,
          color: IdentityColors.muted,
        ),
      ),
    ],
  );
}

class IdentityPanel extends StatelessWidget {
  const IdentityPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 20,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: IdentityColors.line),
    ),
    child: child,
  );
}

class IdentityNotice extends StatelessWidget {
  const IdentityNotice(
    this.text, {
    super.key,
    this.error = false,
    this.icon = Icons.info_outline_rounded,
  });
  final String text;
  final bool error;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : IdentityColors.primary;
    return Semantics(
      liveRegion: error,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline_rounded : icon,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: error ? color : IdentityColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IdentityProgress extends StatelessWidget {
  const IdentityProgress({
    super.key,
    required this.step,
    this.labels = const ['บัตรประชาชน', 'ใบหน้า', 'ข้อมูล', 'ส่งคำขอ'],
  });
  final int step;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ขั้นตอน ${step + 1} จาก ${labels.length} ${labels[step]}',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ขั้นตอน ${step + 1} / ${labels.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: IdentityColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  labels[step],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: IdentityColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              labels.length,
              (index) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index == labels.length - 1 ? 0 : 6,
                  ),
                  height: 5,
                  decoration: BoxDecoration(
                    color: index <= step
                        ? IdentityColors.primary
                        : IdentityColors.line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class IdentityGuide extends StatelessWidget {
  const IdentityGuide({super.key, this.face = false});
  final bool face;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.7,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: IdentityColors.tint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: face
            ? Container(
                width: 100,
                height: 125,
                decoration: BoxDecoration(
                  border: Border.all(color: IdentityColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(65),
                ),
                child: const Icon(
                  Icons.face_outlined,
                  size: 66,
                  color: IdentityColors.primary,
                ),
              )
            : Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: IdentityColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 46,
                      color: IdentityColors.primary,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final width in [1.0, 0.8, 0.55])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: FractionallySizedBox(
                                widthFactor: width,
                                child: Container(
                                  height: 5,
                                  color: IdentityColors.line,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class IdentityTip extends StatelessWidget {
  const IdentityTip(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: IdentityColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: IdentityColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
