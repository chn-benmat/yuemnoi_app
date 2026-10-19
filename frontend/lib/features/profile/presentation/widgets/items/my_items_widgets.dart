import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/user_item.dart';
import '../../bloc/my_items_state.dart';

extension MyItemsFilterStyle on MyItemsFilter {
  String get label => switch (this) {
    MyItemsFilter.available => 'เปิดให้เช่า',
    MyItemsFilter.rented => 'กำลังถูกเช่า',
    MyItemsFilter.hidden => 'กำลังซ่อน',
  };

  Color get foreground => switch (this) {
    MyItemsFilter.available => const Color(0xFF176B47),
    MyItemsFilter.rented => const Color(0xFF315FA6),
    MyItemsFilter.hidden => const Color(0xFF626574),
  };

  IconData get icon => switch (this) {
    MyItemsFilter.available => Icons.check_circle_outline_rounded,
    MyItemsFilter.rented => Icons.schedule_rounded,
    MyItemsFilter.hidden => Icons.visibility_off_outlined,
  };
}

extension MyItemStatusStyle on UserItemStatus {
  String get label => switch (this) {
    UserItemStatus.available => 'เปิดให้เช่า',
    UserItemStatus.rented => 'กำลังถูกเช่า',
    UserItemStatus.unavailable => 'ยังไม่พร้อม',
    UserItemStatus.maintenance => 'อยู่ระหว่างดูแล',
    UserItemStatus.unknown => 'ไม่ระบุสถานะ',
  };

  Color get foreground => switch (this) {
    UserItemStatus.available => const Color(0xFF176B47),
    UserItemStatus.rented => const Color(0xFF315FA6),
    UserItemStatus.maintenance => const Color(0xFF8C5719),
    _ => const Color(0xFF626574),
  };

  Color get background => switch (this) {
    UserItemStatus.available => const Color(0xFFECF7F0),
    UserItemStatus.rented => const Color(0xFFEDF3FF),
    UserItemStatus.maintenance => const Color(0xFFFFF4E5),
    _ => const Color(0xFFF0F1F5),
  };

  IconData get icon => switch (this) {
    UserItemStatus.available => Icons.check_circle_outline_rounded,
    UserItemStatus.rented => Icons.schedule_rounded,
    UserItemStatus.unavailable => Icons.pause_circle_outline_rounded,
    UserItemStatus.maintenance => Icons.build_circle_outlined,
    UserItemStatus.unknown => Icons.help_outline_rounded,
  };
}

class MyItemsFilterSheet extends StatelessWidget {
  const MyItemsFilterSheet({
    super.key,
    this.counts,
    required this.selectedStatus,
    required this.onSelected,
  });
  final Map<MyItemsFilter?, int>? counts;
  final MyItemsFilter? selectedStatus;
  final ValueChanged<MyItemsFilter?> onSelected;

  @override
  Widget build(BuildContext context) {
    final statuses = <MyItemsFilter?>[null, ...MyItemsFilter.values];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'ตัวกรองสถานะ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF242132),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final status in statuses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          key: ValueKey(
                            'my-items-filter-${status?.name ?? 'all'}',
                          ),
                          selected: selectedStatus == status,
                          onTap: () => onSelected(status),
                          selectedColor: AppColors.primaryColor,
                          selectedTileColor: const Color(0xFFF3EAFB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Icon(
                            status?.icon ?? Icons.inventory_2_outlined,
                            color: selectedStatus == status
                                ? AppColors.primaryColor
                                : status?.foreground,
                          ),
                          title: Text(
                            status?.label ?? 'ทั้งหมด',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (counts != null) ...[
                                Text(
                                  '${counts![status] ?? 0}',
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Icon(
                                selectedStatus == status
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selectedStatus == status
                                    ? AppColors.primaryColor
                                    : const Color(0xFFABA6B5),
                              ),
                            ],
                          ),
                        ),
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
}

class MyItemData {
  final int? id;
  final String title;
  final double price;
  final String? imageUrl;
  final IconData iconData;
  final UserItemStatus status;
  final String rentalType;
  final bool ownerHidden;

  const MyItemData({
    this.id,
    required this.title,
    this.price = 0,
    this.imageUrl,
    required this.iconData,
    this.status = UserItemStatus.unknown,
    this.rentalType = '',
    this.ownerHidden = false,
  });

  factory MyItemData.fromEntity(UserItem entity, IconData icon) => MyItemData(
    id: entity.id,
    title: entity.title,
    price: entity.price,
    imageUrl: entity.imageUrl,
    iconData: icon,
    status: entity.listingStatus,
    rentalType: entity.rentalType,
    ownerHidden: entity.ownerHidden,
  );

  String get unitLabel => switch (rentalType.trim().toLowerCase()) {
    'รายชั่วโมง' || 'hour' || 'hourly' => 'ชั่วโมง',
    'รายวัน' || 'day' || 'daily' => 'วัน',
    'รายสัปดาห์' || 'week' || 'weekly' => 'สัปดาห์',
    'รายเดือน' || 'month' || 'monthly' => 'เดือน',
    _ => rentalType.trim().isEmpty ? 'ไม่ระบุหน่วย' : rentalType.trim(),
  };
}

class MyItemCard extends StatelessWidget {
  const MyItemCard({super.key, required this.item, required this.onTap});
  final MyItemData item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final price = NumberFormat('#,##0.##', 'th').format(item.price);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFEAE8EF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 82,
                    height: 96,
                    padding: const EdgeInsets.all(4),
                    color: const Color(0xFFF7F6F9),
                    child: item.imageUrl?.isNotEmpty == true
                        ? Image.network(
                            item.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stack) => _fallbackImage(),
                          )
                        : _fallbackImage(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: Color(0xFF242132),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.ownerHidden
                            ? const Color(0xFFF0F1F5)
                            : item.status.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.ownerHidden
                                ? MyItemsFilter.hidden.icon
                                : item.status.icon,
                            size: 14,
                            color: item.ownerHidden
                                ? MyItemsFilter.hidden.foreground
                                : item.status.foreground,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.ownerHidden
                                  ? MyItemsFilter.hidden.label
                                  : item.status.label,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: item.ownerHidden
                                    ? MyItemsFilter.hidden.foreground
                                    : item.status.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text.rich(
                      TextSpan(
                        text: '฿$price',
                        children: [
                          TextSpan(
                            text: ' / ${item.unitLabel}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF757181),
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF242132),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFABA6B5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackImage() =>
      Icon(item.iconData, color: const Color(0xFFA49AAF), size: 32);
}

class MyItemsMessage extends StatelessWidget {
  const MyItemsMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: Color(0xFFF0E8F9),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: AppColors.primaryColor),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF242132),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            height: 1.65,
            color: Color(0xFF757181),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class MyItemsLoadingSkeleton extends StatelessWidget {
  const MyItemsLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    key: const ValueKey('my-items-skeleton'),
    child: ListView.separated(
      padding: const EdgeInsets.all(20),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 82, height: 96, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FractionallySizedBox(
                    widthFactor: 0.9,
                    child: SkeletonBox(height: 14, borderRadius: 5),
                  ),
                  const SizedBox(height: 7),
                  const FractionallySizedBox(
                    widthFactor: 0.6,
                    child: SkeletonBox(height: 12, borderRadius: 5),
                  ),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: 90, height: 22, borderRadius: 6),
                  const SizedBox(height: 9),
                  const SkeletonBox(width: 75, height: 14, borderRadius: 5),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SkeletonBox(width: 10, height: 14, borderRadius: 5),
          ],
        ),
      ),
    ),
  );
}
