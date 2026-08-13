import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/widgets/app_field_label.dart';
import '../../domain/entities/rental_item.dart';

class RentalItemImagePicker extends StatelessWidget {
  const RentalItemImagePicker({
    super.key,
    required this.images,
    required this.maxImages,
    required this.onAdd,
    required this.onRemove,
    this.errorText,
  });

  final List<RentalItemImage> images;
  final int maxImages;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AppFieldLabel(text: 'รูปภาพ', padding: EdgeInsets.zero),
          Text(
            '${images.length} / $maxImages',
            style: const TextStyle(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 126,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (images.length < maxImages) _AddImageTile(onTap: onAdd),
            for (var index = 0; index < images.length; index++) ...[
              if (index > 0 || images.length < maxImages)
                const SizedBox(width: 14),
              _ImageTile(image: images[index], onRemove: () => onRemove(index)),
            ],
            if (images.isEmpty) ...[
              const SizedBox(width: 14),
              const _EmptyImageTile(),
            ],
          ],
        ),
      ),
      if (errorText != null) ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ],
  );
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('add-rental-images'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(30),
    child: Container(
      width: 128,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFD8DBDD),
          style: BorderStyle.solid,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFE9D8F8),
            child: Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.primaryColor,
            ),
          ),
          SizedBox(height: 14),
          Text('เพิ่มรูป', style: TextStyle(color: AppColors.labelColor)),
        ],
      ),
    ),
  );
}

class _EmptyImageTile extends StatelessWidget {
  const _EmptyImageTile();

  @override
  Widget build(BuildContext context) => Container(
    width: 128,
    decoration: BoxDecoration(
      color: const Color(0xFFEFF0F2),
      borderRadius: BorderRadius.circular(30),
    ),
    child: const Icon(Icons.image_outlined, color: Color(0xFFADB1B4)),
  );
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, required this.onRemove});

  final RentalItemImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.memory(
          image.bytes,
          width: 128,
          height: 126,
          fit: BoxFit.cover,
        ),
      ),
      Positioned(
        right: 6,
        top: 6,
        child: IconButton.filled(
          tooltip: 'ลบรูป',
          onPressed: onRemove,
          style: IconButton.styleFrom(
            backgroundColor: Colors.black54,
            minimumSize: const Size.square(30),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
        ),
      ),
    ],
  );
}
