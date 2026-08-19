import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/services/media_download_service.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';

/// หน้าจอแสดงรูปภาพทั้งหมดในรูปแบบตาราง 2 คอลัมน์ (ตามรูปภาพ Messenger Gallery)
class StackedImagesGridScreen extends StatelessWidget {
  const StackedImagesGridScreen({
    super.key,
    required this.imageUrls,
    this.initialTitle,
  });

  final List<String> imageUrls;
  final String? initialTitle;

  static void open(
    BuildContext context, {
    required List<String> imageUrls,
    String? title,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StackedImagesGridScreen(
          imageUrls: imageUrls,
          initialTitle: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = imageUrls.length;
    final title = initialTitle ?? '$count รูป';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.close_rounded,
            color: Color(0xFF334155),
            size: 28,
          ),
          tooltip: 'ปิด',
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.download_rounded,
              color: AppColors.primaryColor,
              size: 28,
            ),
            tooltip: 'ดาวน์โหลดทั้งหมด',
            onPressed: () async {
              if (imageUrls.isEmpty) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('กำลังบันทึกรูปภาพ $count รูป...'),
                  duration: const Duration(seconds: 1),
                ),
              );
              final savedCount = await MediaDownloadService.instance
                  .saveMultipleImagesFromUrls(imageUrls);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'บันทึก $savedCount รูปภาพลงในแกลเลอรีเรียบร้อยแล้ว',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: imageUrls.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, index) {
          final url = imageUrls[index];
          return GestureDetector(
            onTap: () {
              FullScreenImageViewer.open(
                context,
                imageUrls: imageUrls,
                initialIndex: index,
              );
            },
            child: Hero(
              tag: 'grid-$index-$url',
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFFE2E8F0),
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Color(0xFF94A3B8),
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
