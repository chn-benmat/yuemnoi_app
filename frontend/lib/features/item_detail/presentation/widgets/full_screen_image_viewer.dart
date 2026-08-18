import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
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
  final Map<int, TransformationController> _transformControllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1,
    );
    _pageController = PageController(initialPage: _currentIndex);
  }

  TransformationController _getController(int index) {
    return _transformControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  void _handleDoubleTap(int index) {
    final controller = _getController(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
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
            PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                // Reset zoom on other pages
                for (final entry in _transformControllers.entries) {
                  if (entry.key != index) {
                    entry.value.value = Matrix4.identity();
                  }
                }
              },
              itemBuilder: (context, index) {
                final controller = _getController(index);
                return GestureDetector(
                  onDoubleTap: () => _handleDoubleTap(index),
                  child: Center(
                    child: InteractiveViewer(
                      transformationController: controller,
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: urls[index],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // Top action bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFFF43F5E),
                        size: 28,
                      ),
                      tooltip: 'ปิด',
                      onPressed: () => Navigator.of(context).pop(),
                    ),

                    // Counter badge if multiple
                    if (urls.length > 1)
                      Text(
                        '${_currentIndex + 1}/${urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                    // Download button
                    IconButton(
                      icon: const Icon(
                        Icons.download_rounded,
                        color: Color(0xFFF43F5E),
                        size: 28,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
