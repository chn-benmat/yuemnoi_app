import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../core/services/media_download_service.dart';

class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenImageViewer(
              imageUrls: imageUrls,
              initialIndex: initialIndex,
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
    final urls = widget.imageUrls;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top + 56.0;
    final bottomPadding = mediaQuery.padding.bottom + 24.0;

    return Scaffold(
      backgroundColor: const Color(0xFF7A09A3),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8B12BA), Color(0xFF6E0099), Color(0xFF4C006E)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (urls.isEmpty)
              const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              )
            else
              Padding(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
                child: PhotoViewGallery.builder(
                  pageController: _pageController,
                  itemCount: urls.length,
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  onPageChanged: (index) =>
                      setState(() => _currentIndex = index),
                  loadingBuilder: (context, progress) => const Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                  builder: (context, index) => PhotoViewGalleryPageOptions(
                    imageProvider: CachedNetworkImageProvider(urls[index]),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained * 0.8,
                    maxScale: PhotoViewComputedScale.contained * 4,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),

            // Top action bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Close button
                      Container(
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

                      // Counter badge if multiple
                      if (urls.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_currentIndex + 1}/${urls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      // Download button
                      Container(
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
                          tooltip: 'บันทึกรูปภาพ',
                          onPressed: () async {
                            if (urls.isEmpty) return;
                            final currentUrl = urls[_currentIndex];
                            final success = await MediaDownloadService.instance
                                .saveImageFromUrl(currentUrl);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'บันทึกรูปภาพลงในแกลเลอรีเรียบร้อยแล้ว'
                                        : 'ไม่สามารถบันทึกรูปภาพได้ กรุณาลองใหม่',
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
