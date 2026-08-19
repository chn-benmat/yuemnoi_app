import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class BookingLocationCard extends StatelessWidget {
  const BookingLocationCard({
    super.key,
    required this.location,
    required this.locationNote,
    this.onLocationChanged,
    this.isEditable = true,
  });

  final String location;
  final String locationNote;
  final ValueChanged<String>? onLocationChanged;
  final bool isEditable;

  void _showLocationPicker(BuildContext context) {
    if (!isEditable || onLocationChanged == null) return;

    final controller = TextEditingController(text: location);
    final popularLocations = [
      'ซีคอน บางแค',
      'สยามพารากอน (Siam Paragon)',
      'เซ็นทรัล ลาดพร้าว (Central Ladprao)',
      'เมกา บางนา (Mega Bangna)',
      'ไอคอนสยาม (ICONSIAM)',
      'ฟิวเจอร์พาร์ค รังสิต',
      'BTS หมอชิต / MRT สวนจตุจักร',
      'BTS อโศก / MRT สุขุมวิท',
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E2E5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'เปลี่ยนสถานที่นัดพบ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'พิมพ์ระบุสถานที่นัดพบ...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF777A7C),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF2F4F7),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'สถานที่ยอดนิยม:',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF777A7C),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: popularLocations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF0F1F2)),
                  itemBuilder: (context, index) {
                    final spot = popularLocations[index];
                    final isCurrent = spot == location;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.place_outlined,
                        color: isCurrent ? AppColors.primaryColor : const Color(0xFF777A7C),
                        size: 20,
                      ),
                      title: Text(
                        spot,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? AppColors.primaryColor : const Color(0xFF1E2022),
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check_rounded, color: AppColors.primaryColor, size: 20)
                          : null,
                      onTap: () {
                        onLocationChanged!(spot);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      onLocationChanged!(text);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    'บันทึกสถานที่',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'สถานที่นัดพบ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.primaryColor,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E2022),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationNote,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF777A7C),
                      ),
                    ),
                  ],
                ),
              ),
              if (isEditable)
                IconButton(
                  tooltip: 'แก้ไขสถานที่',
                  onPressed: () => _showLocationPicker(context),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF595C5D),
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
