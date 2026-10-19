import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';

class ChatItemHeaderCard extends StatelessWidget {
  const ChatItemHeaderCard({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.itemImageUrl,
    required this.itemPrice,
    required this.itemRentalType,
  });

  final int itemId;
  final String itemName;
  final String? itemImageUrl;
  final int? itemPrice;
  final String? itemRentalType;

  @override
  Widget build(BuildContext context) {
    final unitLabel =
        (itemRentalType == 'รายชั่วโมง' ||
            itemRentalType == 'hourly' ||
            itemRentalType == 'hour')
        ? 'ชั่วโมง'
        : 'วัน';
    final priceStr = itemPrice != null
        ? '${NumberFormat.decimalPattern().format(itemPrice)} ฿ / $unitLabel'
        : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => AppRoutes.openItemDetail(context, itemId: itemId),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: (itemImageUrl != null && itemImageUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: itemImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const ColoredBox(
                              color: Color(0xFFEEEEEE),
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (_, _, _) => const ColoredBox(
                              color: Color(0xFFEEEEEE),
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey,
                                size: 24,
                              ),
                            ),
                          )
                        : const ColoredBox(
                            color: Color(0xFFEEEEEE),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.grey,
                              size: 24,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2C2D30),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (priceStr.isNotEmpty)
                        Text(
                          priceStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryColor,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9E9EA4),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
