import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
        builder: (context) =>
            StackedImagesGridScreen(imageUrls: imageUrls, initialTitle: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = imageUrls.length;
    final title = initialTitle ?? '$count รูป';

    return Scaffold(
      backgroundColor: const Color(0xFF7A09A3),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
            tooltip: 'ปิด',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        centerTitle: true,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(
                Icons.download_rounded,
                color: Colors.white,
                size: 26,
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
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8B12BA), Color(0xFF6E0099), Color(0xFF4C006E)],
          ),
        ),
        child: GridView.builder(
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
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black12,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white60,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
