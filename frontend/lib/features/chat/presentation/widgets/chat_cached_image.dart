import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/cache/network_image_cache_key.dart';
import '../../../item_detail/presentation/widgets/full_screen_image_viewer.dart';
import '../../data/datasources/chat_remote_data_source.dart';

class ChatCachedImage extends StatefulWidget {
  const ChatCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.refreshImageUrl,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final Future<String> Function(String)? refreshImageUrl;

  static Future<void> openFullScreen(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) => FullScreenImageViewer.open(
    context,
    imageUrls: imageUrls,
    initialIndex: initialIndex,
    refreshImageUrl: ChatRemoteDataSource().refreshChatImageUrl,
  );

  @override
  State<ChatCachedImage> createState() => _ChatCachedImageState();
}

class _ChatCachedImageState extends State<ChatCachedImage> {
  String? _resolvedUrl;
  String? _identity;
  bool _attemptedRecovery = false;

  @override
  void didUpdateWidget(covariant ChatCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolvedUrl = null;
      _attemptedRecovery = false;
    }
  }

  Future<void> _refresh(String failedUrl, String original, String scope) async {
    if (!mounted ||
        _attemptedRecovery ||
        widget.imageUrl != original ||
        networkImageCacheKey(widget.imageUrl) != scope ||
        (_resolvedUrl ?? widget.imageUrl) != failedUrl)
      return;
    _attemptedRecovery = true;
    try {
      final fresh =
          await (widget.refreshImageUrl ??
              ChatRemoteDataSource().refreshChatImageUrl)(failedUrl);
      if (mounted &&
          widget.imageUrl == original &&
          networkImageCacheKey(original) == scope &&
          fresh != failedUrl) {
        setState(() {
          _resolvedUrl = fresh;
        });
      }
    } catch (_) {
      // ข้อผิดพลาดของรูปไม่ควรขัดขวางการอ่านหรือส่งข้อความ
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.imageUrl;
    final scope = networkImageCacheKey(original);
    if (_identity != scope) {
      _identity = scope;
      _resolvedUrl = null;
      _attemptedRecovery = false;
    }
    return CachedNetworkImage(
      // ลิงก์ใหม่ต้องลองเปิด stream ใหม่ได้ แม้ stream เดิมเคยล้มเหลว
      key: ValueKey((scope, _resolvedUrl ?? original)),
      imageUrl: _resolvedUrl ?? widget.imageUrl,
      cacheKey: scope,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: widget.placeholder,
      errorWidget: (context, url, error) {
        if (!_attemptedRecovery) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _refresh(url, original, scope),
          );
        }
        return widget.errorWidget?.call(context, url, error) ??
            const Icon(Icons.image_not_supported_outlined);
      },
    );
  }
}
