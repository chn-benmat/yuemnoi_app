import 'package:frontend/core/widgets/app_popup.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/cache/network_image_cache_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../core/services/media_download_service.dart';
import '../../../../core/theme/media_gallery_style.dart';

class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.refreshImageUrl,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final Future<String> Function(String)? refreshImageUrl;

  static Future<void> open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
    Future<String> Function(String)? refreshImageUrl,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenImageViewer(
              imageUrls: imageUrls,
              initialIndex: initialIndex,
              refreshImageUrl: refreshImageUrl,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final _resolvedUrls = <String, String>{};
  final _attempted = <String>{};
  List<String> _identities = [];
  bool _saving = false;

  Future<void> _saveCurrent(String url) async {
    if (_saving) return;
    setState(() => _saving = true);
    var success = false;
    try {
      success = await MediaDownloadService.instance.saveImageFromUrl(url);
    } catch (_) {
      // แสดงผลล้มเหลวและคืนปุ่มให้ลองใหม่ได้
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) {
      return;
    }
    showAppPopup(
      context,
      content: Text('บันทึกไม่สำเร็จ โปรดตรวจสอบสิทธิ์รูปภาพแล้วลองใหม่'),
    );
  }

  Future<void> _recover(
    int index,
    String original,
    String identity,
    String failedUrl,
  ) async {
    final resolve = widget.refreshImageUrl;
    if (!mounted ||
        resolve == null ||
        index >= widget.imageUrls.length ||
        widget.imageUrls[index] != original ||
        networkImageCacheKey(original) != identity ||
        (_resolvedUrls[identity] ?? original) != failedUrl ||
        !_attempted.add(identity))
      return;
    try {
      final fresh = await resolve(failedUrl);
      if (mounted &&
          index < widget.imageUrls.length &&
          widget.imageUrls[index] == original &&
          networkImageCacheKey(original) == identity &&
          fresh != failedUrl) {
        setState(() {
          _resolvedUrls[identity] = fresh;
        });
      }
    } catch (_) {
      // แสดงข้อผิดพลาดของรูปเดิมโดยไม่รบกวนการปิดหรือเลื่อนแกลเลอรี
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identities = widget.imageUrls.map(networkImageCacheKey).toList();
    if (!listEquals(_identities, identities)) {
      _identities = identities;
      _resolvedUrls.clear();
      _attempted.clear();
    }
    final urls = [
      for (var i = 0; i < widget.imageUrls.length; i++)
        _resolvedUrls[identities[i]] ?? widget.imageUrls[i],
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MediaGalleryStyle.darkSystemUi,
      child: Scaffold(
        backgroundColor: MediaGalleryStyle.viewerBackground,
        appBar: AppBar(
          systemOverlayStyle: MediaGalleryStyle.darkSystemUi,
          backgroundColor: MediaGalleryStyle.viewerBackground,
          surfaceTintColor: MediaGalleryStyle.viewerBackground,
          foregroundColor: MediaGalleryStyle.surface,
          elevation: 0,
          toolbarHeight: 72,
          leadingWidth: 72,
          leading: Padding(
            padding: const EdgeInsets.all(12),
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close_rounded, size: 24),
              tooltip: 'ปิด',
              style: IconButton.styleFrom(
                backgroundColor: MediaGalleryStyle.viewerSurface,
                foregroundColor: MediaGalleryStyle.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          centerTitle: true,
          title: Column(
            children: [
              const Text(
                'รูปภาพ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (urls.isNotEmpty)
                Text(
                  '${_currentIndex + 1}/${urls.length}',
                  style: const TextStyle(
                    color: MediaGalleryStyle.viewerMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          actions: const [SizedBox(width: 72)],
        ),
        body: urls.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      color: MediaGalleryStyle.viewerMuted,
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'ยังไม่มีรูปภาพ',
                      style: TextStyle(color: MediaGalleryStyle.viewerMuted),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: PhotoViewGallery.builder(
                  key: ValueKey((identities.join('|'), urls.join('|'))),
                  pageController: _pageController,
                  itemCount: urls.length,
                  backgroundDecoration: const BoxDecoration(
                    color: MediaGalleryStyle.viewerBackground,
                  ),
                  onPageChanged: (index) =>
                      setState(() => _currentIndex = index),
                  loadingBuilder: (context, progress) => const Center(
                    child: SizedBox.square(
                      dimension: 32,
                      child: CircularProgressIndicator(
                        color: MediaGalleryStyle.viewerMuted,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  builder: (context, index) => PhotoViewGalleryPageOptions(
                    imageProvider: CachedNetworkImageProvider(
                      urls[index],
                      cacheKey: identities[index],
                    ),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained * 0.8,
                    maxScale: PhotoViewComputedScale.contained * 4,
                    errorBuilder: (context, error, stackTrace) {
                      final original = widget.imageUrls[index];
                      final identity = identities[index];
                      if (!_attempted.contains(identity) &&
                          widget.refreshImageUrl != null) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) =>
                              _recover(index, original, identity, urls[index]),
                        );
                      }
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: MediaGalleryStyle.viewerMuted,
                              size: 48,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'โหลดรูปไม่สำเร็จ',
                              style: TextStyle(
                                color: MediaGalleryStyle.viewerMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (urls.isNotEmpty) ...[
                Text(
                  urls.length > 1
                      ? 'ปัดเพื่อเปลี่ยนรูป · ใช้สองนิ้วเพื่อซูม'
                      : 'ใช้สองนิ้วเพื่อซูมดูรายละเอียด',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MediaGalleryStyle.viewerMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _saving || urls.isEmpty
                    ? null
                    : () => _saveCurrent(urls[_currentIndex]),
                style: MediaGalleryStyle.saveButtonStyle.copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? MediaGalleryStyle.viewerSurface
                        : MediaGalleryStyle.accent,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? MediaGalleryStyle.viewerMuted
                        : MediaGalleryStyle.surface,
                  ),
                ),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MediaGalleryStyle.viewerMuted,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 22),
                label: Text(
                  _saving ? 'กำลังบันทึก…' : 'บันทึกรูปภาพ',
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
