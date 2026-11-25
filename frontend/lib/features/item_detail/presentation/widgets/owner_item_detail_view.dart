import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/pickup_location_field.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../domain/entities/item_detail.dart';
import 'full_screen_image_viewer.dart';
import 'owner_item_controls.dart';

class OwnerItemDetailView extends StatelessWidget {
  const OwnerItemDetailView({
    super.key,
    required this.item,
    required this.busy,
    required this.deleting,
    required this.onRefresh,
    required this.onVisibilityChanged,
    required this.onEditBasic,
    required this.onAutoReply,
    required this.onDelete,
  });

  final ItemDetail item;
  final bool busy;
  final bool deleting;
  final Future<void> Function() onRefresh;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onEditBasic;
  final VoidCallback onAutoReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      color: Color(0xFF211C35),
    ),
    child: RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('owner-item-detail-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OwnerItemPhotos(urls: item.imageUrls),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final (price, unit) in [
                              (item.price, item.unitLabel),
                              if (item.additionalDailyPrice
                                  case final dailyPrice?)
                                (dailyPrice, 'วัน'),
                            ])
                              Text.rich(
                                TextSpan(
                                  text:
                                      '฿${NumberFormat('#,##0.##', 'th').format(price)}',
                                  children: [
                                    TextSpan(
                                      text: ' / $unit',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF817A91),
                                      ),
                                    ),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (item.pickupLocation != null)
                    PickupLocationCard(location: item.pickupLocation!),
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
                        const Padding(
                          padding: EdgeInsets.fromLTRB(2, 2, 2, 10),
                          child: Text(
                            'การแสดงผล',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        OwnerItemVisibility(
                          hidden: item.ownerHidden,
                          busy: busy,
                          onChanged: onVisibilityChanged,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _ManagementRow(
                          id: 'basic',
                          icon: Icons.description_outlined,
                          title: 'แก้ไขอุปกรณ์',
                          onTap: busy ? null : onEditBasic,
                        ),
                        const _MenuDivider(),
                        _ManagementRow(
                          id: 'auto-reply',
                          icon: Icons.quickreply_outlined,
                          title: 'ข้อความตอบกลับอัตโนมัติ',
                          onTap: busy ? null : onAutoReply,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  OwnerItemDeleteButton(
                    busy: busy,
                    deleting: deleting,
                    onPressed: onDelete,
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

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 52, right: 16),
    child: Divider(height: 1, color: Color(0xFFF1EEF5)),
  );
}

class _ManagementRow extends StatelessWidget {
  const _ManagementRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final String id;
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('owner-edit-$id'),
    onTap: onTap,
    enabled: onTap != null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    minLeadingWidth: 22,
    horizontalTitleGap: 14,
    minTileHeight: 52,
    leading: Icon(icon, size: 22, color: const Color(0xFF302A48)),
    title: Text(
      title,
      style: const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 22,
      color: Color(0xFF9D96AD),
    ),
  );
}

class _OwnerItemPhotos extends StatefulWidget {
  const _OwnerItemPhotos({required this.urls});
  final List<String> urls;
  @override
  State<_OwnerItemPhotos> createState() => _OwnerItemPhotosState();
}

class _OwnerItemPhotosState extends State<_OwnerItemPhotos> {
  int _page = 0;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: AspectRatio(
      aspectRatio: 1.5,
      child: ColoredBox(
        color: Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.urls.isEmpty)
              const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: Color(0xFFB9B4C4),
                ),
              )
            else
              PageView.builder(
                itemCount: widget.urls.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => FullScreenImageViewer.open(
                    context,
                    imageUrls: widget.urls,
                    initialIndex: index,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[index],
                    fit: BoxFit.contain,
                    placeholder: (_, url) => const SkeletonShimmer(
                      child: ColoredBox(color: Color(0xFFF0EDF4)),
                    ),
                    errorWidget: (_, url, error) => const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFFB9B4C4),
                      size: 48,
                    ),
                  ),
                ),
              ),
            if (widget.urls.length > 1)
              Positioned(
                right: 10,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F1F8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '${_page + 1}/${widget.urls.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF716A83),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
