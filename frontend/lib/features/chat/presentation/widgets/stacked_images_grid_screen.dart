import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/media_download_service.dart';
import '../../../../core/theme/media_gallery_style.dart';
import 'chat_cached_image.dart';

/// อัลบั้มรูปในแชต แสดงตัวอย่างโดยไม่ตัดเนื้อหารูปออก
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
  Widget build(BuildContext context) =>
      _GalleryContent(imageUrls: imageUrls, title: initialTitle);
}

class _GalleryContent extends StatefulWidget {
  const _GalleryContent({required this.imageUrls, this.title});

  final List<String> imageUrls;
  final String? title;

  @override
  State<_GalleryContent> createState() => _GalleryContentState();
}

class _GalleryContentState extends State<_GalleryContent> {
  bool _saving = false;

  Future<void> _saveAll() async {
    if (_saving || widget.imageUrls.isEmpty) return;
    final urls = List<String>.of(widget.imageUrls);
    setState(() => _saving = true);
    var saved = 0;
    try {
      saved = await MediaDownloadService.instance.saveMultipleImagesFromUrls(
        urls,
      );
    } catch (_) {
      // ปฏิเสธสิทธิ์หรือล้มเหลวต้องยังกลับมาลองบันทึกใหม่ได้
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final count = urls.length;
    final message = saved == count
        ? 'บันทึกครบ $count รูปแล้ว'
        : saved > 0
        ? 'บันทึกได้ $saved จาก $count รูป กรุณาลองใหม่อีกครั้ง'
        : 'บันทึกไม่สำเร็จ โปรดตรวจสอบสิทธิ์รูปภาพแล้วลองใหม่';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.imageUrls.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MediaGalleryStyle.lightSystemUi,
      child: Scaffold(
        backgroundColor: MediaGalleryStyle.background,
        appBar: AppBar(
          backgroundColor: MediaGalleryStyle.background,
          surfaceTintColor: MediaGalleryStyle.background,
          foregroundColor: MediaGalleryStyle.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 72,
          leadingWidth: 72,
          leading: Padding(
            padding: const EdgeInsets.all(12),
            child: IconButton.filledTonal(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'ปิด',
              style: IconButton.styleFrom(
                backgroundColor: MediaGalleryStyle.surface,
                foregroundColor: MediaGalleryStyle.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 24),
            ),
          ),
          titleSpacing: 4,
          title: Text(
            widget.title ?? 'อัลบั้มรูป',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 24),
              child: Icon(
                Icons.photo_library_outlined,
                color: MediaGalleryStyle.accent,
                size: 24,
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      const Text(
                        'รูปภาพในแชต',
                        style: TextStyle(
                          color: MediaGalleryStyle.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: MediaGalleryStyle.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count รูป',
                          style: const TextStyle(
                            color: MediaGalleryStyle.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'แตะรูปเพื่อดูเต็มจอและซูม',
                    style: TextStyle(
                      color: MediaGalleryStyle.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: count == 0
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            color: MediaGalleryStyle.muted,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'ยังไม่มีรูปภาพในอัลบั้มนี้',
                            style: TextStyle(color: MediaGalleryStyle.muted),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: count,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: constraints.maxWidth >= 900
                              ? 4
                              : constraints.maxWidth >= 600
                              ? 3
                              : 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.70,
                        ),
                        itemBuilder: (context, index) => _AlbumTile(
                          imageUrl: widget.imageUrls[index],
                          index: index,
                          onTap: () => ChatCachedImage.openFullScreen(
                            context,
                            imageUrls: widget.imageUrls,
                            initialIndex: index,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: MediaGalleryStyle.surface,
            border: Border(top: BorderSide(color: MediaGalleryStyle.border)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: FilledButton.icon(
              onPressed: _saving || count == 0 ? null : _saveAll,
              style: MediaGalleryStyle.saveButtonStyle,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MediaGalleryStyle.accent,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 22),
              label: Text(
                _saving ? 'กำลังบันทึก…' : 'บันทึกทั้งหมด',
                maxLines: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.imageUrl,
    required this.index,
    required this.onTap,
  });

  final String imageUrl;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'เปิดรูปที่ ${index + 1} เต็มจอ',
    child: Material(
      color: MediaGalleryStyle.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: MediaGalleryStyle.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ChatCachedImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, _) => const ColoredBox(
                      color: MediaGalleryStyle.background,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MediaGalleryStyle.accent,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => const ColoredBox(
                      color: MediaGalleryStyle.background,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: MediaGalleryStyle.muted,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'รูปที่ ${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MediaGalleryStyle.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.open_in_full_rounded,
                    color: MediaGalleryStyle.accent,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
