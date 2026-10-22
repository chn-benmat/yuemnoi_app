import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/profile_storefront.dart';

class ProfileReviewsSheet extends StatelessWidget {
  const ProfileReviewsSheet({super.key, required this.storefront});

  final ProfileStorefront storefront;

  @override
  Widget build(BuildContext context) {
    final reviews = [...storefront.reviewDetails]
      ..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );
    final itemNames = {
      for (final entry in storefront.items) entry.item.id: entry.item.title,
    };
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          color: Color(0xFF24212C),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'รีวิวทั้งหมด (${reviews.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (storefront.reviews != null && storefront.reviews!.count > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '★ ${storefront.reviews!.average.toStringAsFixed(1)} / 5',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: reviews.isEmpty
                  ? const Center(child: Text('ยังไม่มีรีวิว'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: reviews.length,
                      separatorBuilder: (_, _) => const Divider(height: 32),
                      itemBuilder: (context, index) {
                        final review = reviews[index];
                        final avatar = review.avatarUrl;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipOval(
                                  child: avatar != null && avatar.isNotEmpty
                                      ? Image.network(
                                          avatar,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const _ReviewerPlaceholder(),
                                        )
                                      : const _ReviewerPlaceholder(),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    review.reviewerName.isEmpty
                                        ? 'ผู้ใช้'
                                        : review.reviewerName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '★ ${review.rating.toStringAsFixed(1)}',
                                  semanticsLabel: '${review.rating} จาก 5 ดาว',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            if (review.createdAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(review.createdAt!.toLocal()),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              review.description.trim().isEmpty
                                  ? 'ให้คะแนนโดยไม่ได้เขียนข้อความ'
                                  : review.description,
                              style: const TextStyle(fontSize: 14, height: 1.6),
                            ),
                            if (itemNames[review.itemId]
                                case final String name) ...[
                              const SizedBox(height: 10),
                              Text(
                                'อุปกรณ์: $name',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewerPlaceholder extends StatelessWidget {
  const _ReviewerPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    color: AppColors.bgFieldColor,
    child: const Icon(
      Icons.person_outline_rounded,
      color: AppColors.primaryColor,
    ),
  );
}
