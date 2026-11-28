import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_shimmer.dart';

class OwnerItemDetailLoadingView extends StatelessWidget {
  const OwnerItemDetailLoadingView({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'กำลังโหลดรายละเอียดอุปกรณ์',
    child: ExcludeSemantics(
      key: const ValueKey('owner-item-detail-skeleton'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SkeletonShimmer(
                    child: AspectRatio(
                      key: ValueKey('owner-photo-skeleton'),
                      aspectRatio: 1.5,
                      child: SkeletonBox(
                        height: double.infinity,
                        borderRadius: 14,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: SkeletonShimmer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 290, height: 30, borderRadius: 7),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              SkeletonBox(
                                width: 96,
                                height: 30,
                                borderRadius: 7,
                              ),
                              SizedBox(width: 20),
                              SkeletonBox(
                                width: 84,
                                height: 30,
                                borderRadius: 7,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // แถวจุดนัดรับแบบ PickupLocationCard ซึ่งอุปกรณ์ส่วนใหญ่มี
                  const SkeletonShimmer(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SkeletonBox(
                        width: 24,
                        height: 24,
                        shape: BoxShape.circle,
                      ),
                      title: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SkeletonBox(
                          width: 110,
                          height: 15,
                          borderRadius: 6,
                        ),
                      ),
                      subtitle: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SkeletonBox(
                            width: 170,
                            height: 13,
                            borderRadius: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE7E3EE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(2, 2, 2, 10),
                            child: SkeletonShimmer(
                              child: SkeletonBox(
                                width: 100,
                                height: 24,
                                borderRadius: 6,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFECE4F4)),
                          ),
                          child: const SkeletonShimmer(
                            child: Row(
                              children: [
                                SkeletonBox(
                                  width: 22,
                                  height: 22,
                                  borderRadius: 6,
                                ),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(
                                        width: 120,
                                        height: 15,
                                        borderRadius: 6,
                                      ),
                                      SizedBox(height: 10),
                                      SkeletonBox(
                                        width: 170,
                                        height: 12,
                                        borderRadius: 5,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 12),
                                SkeletonBox(
                                  width: 48,
                                  height: 28,
                                  borderRadius: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        SkeletonShimmer(
                          child: _ManagementRowSkeleton(width: 120),
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 52, right: 16),
                          child: Divider(height: 1, color: Color(0xFFF1EEF5)),
                        ),
                        SkeletonShimmer(
                          child: _ManagementRowSkeleton(width: 180),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SkeletonShimmer(
                    child: SkeletonBox(height: 52, borderRadius: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ManagementRowSkeleton extends StatelessWidget {
  const _ManagementRowSkeleton({required this.width});
  final double width;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      height: 52,
      child: Row(
        children: [
          const SkeletonBox(width: 22, height: 22, borderRadius: 6),
          const SizedBox(width: 14),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: width, height: 14, borderRadius: 6),
            ),
          ),
          const SizedBox(width: 12),
          // ลูกศร chevron ขนาด 22 ของ _ManagementRow
          const SkeletonBox(width: 22, height: 22, borderRadius: 6),
        ],
      ),
    ),
  );
}
