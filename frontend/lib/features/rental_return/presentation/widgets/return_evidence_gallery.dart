import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';

class ReturnEvidenceGallery extends StatelessWidget {
  const ReturnEvidenceGallery({super.key, required this.photos});

  final List<ReturnInspectionPhoto> photos;

  @override
  Widget build(BuildContext context) {
    final savedPhotos = photos.where((photo) => photo.hasPhoto);
    if (savedPhotos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ภาพตรวจสภาพที่บันทึกไว้',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final photo in savedPhotos)
              InkWell(
                onTap: () => _showImageDialog(context, photo),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: photo.imageUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _showImageDialog(BuildContext context, ReturnInspectionPhoto photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    photo.angleTitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: photo.imageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (c, u, e) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'บันทึกเมื่อ: ${photo.formattedTime} | รหัส: ${photo.challengeCode}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Colors.white70,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
