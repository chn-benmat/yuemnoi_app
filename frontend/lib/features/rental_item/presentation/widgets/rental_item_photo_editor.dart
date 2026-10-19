import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_form_field_styles.dart';
import '../../domain/entities/rental_item.dart';

class RentalItemPhotoView extends StatelessWidget {
  const RentalItemPhotoView({
    super.key,
    required this.photo,
    this.fit = BoxFit.contain,
  });

  final RentalItemPhoto photo;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    const fallback = Center(
      child: Icon(Icons.image_not_supported_outlined, size: 36),
    );
    return ColoredBox(
      color: AppFormFieldStyles.outlinedDisabledColor,
      child: photo.remoteUrl != null
          ? CachedNetworkImage(
              imageUrl: photo.remoteUrl!,
              fit: fit,
              placeholder: (_, _) =>
                  const Center(child: Icon(Icons.image_outlined, size: 36)),
              errorWidget: (_, _, _) => fallback,
            )
          : Image.memory(
              photo.localImage!.bytes,
              fit: fit,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class RentalItemPhotoEditor extends StatefulWidget {
  const RentalItemPhotoEditor({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    this.isPicking = false,
    this.errorText,
  });

  final List<RentalItemPhoto> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final bool isPicking;
  final String? errorText;

  @override
  State<RentalItemPhotoEditor> createState() => _RentalItemPhotoEditorState();
}

class _RentalItemPhotoEditorState extends State<RentalItemPhotoEditor> {
  final _pages = PageController();
  final _thumbnails = ScrollController();
  late List<RentalItemPhoto> _lastPhotos;
  RentalItemPhoto? _visiblePhoto;
  int _index = 0;
  bool _syncingPhotos = false;

  @override
  void initState() {
    super.initState();
    _lastPhotos = [...widget.photos];
    _visiblePhoto = widget.photos.firstOrNull;
  }

  @override
  void didUpdateWidget(covariant RentalItemPhotoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(_lastPhotos, widget.photos)) return;
    _lastPhotos = [...widget.photos];
    final retainedIndex = _visiblePhoto == null
        ? -1
        : widget.photos.indexOf(_visiblePhoto!);
    _index = retainedIndex >= 0
        ? retainedIndex
        : _index.clamp(0, widget.photos.isEmpty ? 0 : widget.photos.length - 1);
    _visiblePhoto = widget.photos.isEmpty ? null : widget.photos[_index];
    _syncingPhotos = true;
    final selectedIndex = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pages.hasClients) _pages.jumpToPage(selectedIndex);
      _syncingPhotos = false;
      _revealThumbnail(selectedIndex);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _thumbnails.dispose();
    super.dispose();
  }

  void _revealThumbnail(int index) {
    if (!_thumbnails.hasClients) return;
    final position = _thumbnails.position;
    final start = index * 92.0;
    final end = start + 84;
    final target = start < position.pixels
        ? start
        : end > position.pixels + position.viewportDimension
        ? end - position.viewportDimension
        : position.pixels;
    final offset = target.clamp(0.0, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _thumbnails.jumpTo(offset);
    } else {
      _thumbnails.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectPhoto(int index) {
    if (index < 0 || index >= widget.photos.length) return;
    setState(() {
      _index = index;
      _visiblePhoto = widget.photos[index];
    });
    if (_pages.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(index);
      } else {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
    _revealThumbnail(index);
  }

  void _pageChanged(int index) {
    if (_syncingPhotos || index >= widget.photos.length) return;
    setState(() {
      _index = index;
      _visiblePhoto = widget.photos[index];
    });
    _revealThumbnail(index);
  }

  void _preview(int index) {
    showDialog<void>(
      context: context,
      builder: (_) => _RentalPhotoPreview(
        photos: List.of(widget.photos),
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final borderColor = widget.errorText == null
        ? AppFormFieldStyles.outlinedBorderColor
        : Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'รูปภาพอุปกรณ์',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${photos.length} / 5',
              style: const TextStyle(
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'เพิ่มอย่างน้อย 1 รูป รูปแรกจะแสดงเป็นรูปปก',
          style: TextStyle(
            color: AppFormFieldStyles.outlinedHintColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),
        if (photos.isEmpty)
          Material(
            color: AppFormFieldStyles.outlinedHoverColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('rental-photo-add'),
              onTap: widget.isPicking ? null : widget.onAdd,
              child: SizedBox(
                width: double.infinity,
                height: MediaQuery.textScalerOf(context).scale(186),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isPicking)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primaryColor,
                        size: 34,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      widget.isPicking
                          ? 'กำลังเตรียมรูปภาพ…'
                          : 'เพิ่มรูปอุปกรณ์',
                      style: const TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'เลือกรูปที่เห็นอุปกรณ์ชัดเจน สูงสุด 5 รูป',
                      style: TextStyle(
                        color: AppFormFieldStyles.outlinedHintColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 1.75,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    key: const Key('rental-photo-pages'),
                    controller: _pages,
                    itemCount: photos.length,
                    onPageChanged: _pageChanged,
                    itemBuilder: (context, index) => Semantics(
                      button: true,
                      label: 'ดูรูปที่ ${index + 1} ขนาดเต็ม',
                      child: GestureDetector(
                        onTap: () => _preview(index),
                        child: RentalItemPhotoView(photo: photos[index]),
                      ),
                    ),
                  ),
                  if (_index == 0)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'รูปปก',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'รูปที่ ${_index + 1} / ${photos.length}',
                    key: const Key('rental-photo-position'),
                    style: const TextStyle(
                      color: AppFormFieldStyles.outlinedHintColor,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('rental-photo-set-cover'),
                  onPressed: _index == 0
                      ? null
                      : () => widget.onReorder(_index, 0),
                  icon: Icon(
                    _index == 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.photo_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'ตั้งเป็นรูปปก',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: ReorderableListView.builder(
              scrollController: _thumbnails,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: photos.length,
              onReorderItem: widget.onReorder,
              proxyDecorator: (child, _, _) => Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
              footer: photos.length < 5
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: OutlinedButton(
                        key: const Key('rental-photo-add'),
                        onPressed: widget.isPicking ? null : widget.onAdd,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: widget.isPicking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_rounded),
                                  SizedBox(height: 4),
                                  Text(
                                    'เพิ่มรูป',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                      ),
                    )
                  : null,
              itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
                key: ObjectKey(photos[index]),
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 84,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: index == _index
                            ? AppColors.primaryColor
                            : borderColor,
                        width: index == _index ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Semantics(
                          button: true,
                          selected: index == _index,
                          label:
                              'แสดงรูปที่ ${index + 1}${index == 0 ? ' รูปปก' : ''}',
                          child: GestureDetector(
                            key: ValueKey('rental-photo-thumbnail-$index'),
                            onTap: () => _selectPhoto(index),
                            child: RentalItemPhotoView(
                              photo: photos[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            key: ValueKey('rental-photo-remove-$index'),
                            tooltip: 'ลบรูปที่ ${index + 1}',
                            onPressed: () => widget.onRemove(index),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              maximumSize: const Size(44, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            icon: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'ปัดรูปใหญ่หรือแตะรูปย่อเพื่อดู กดค้างรูปย่อเพื่อลากเรียง',
            style: TextStyle(
              color: AppFormFieldStyles.outlinedHintColor,
              fontSize: 12,
            ),
          ),
        ],
        if (widget.errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _RentalPhotoPreview extends StatefulWidget {
  const _RentalPhotoPreview({required this.photos, required this.initialIndex});
  final List<RentalItemPhoto> photos;
  final int initialIndex;

  @override
  State<_RentalPhotoPreview> createState() => _RentalPhotoPreviewState();
}

class _RentalPhotoPreviewState extends State<_RentalPhotoPreview> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: AspectRatio(
      aspectRatio: 0.85,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) => InteractiveViewer(
              child: RentalItemPhotoView(photo: widget.photos[index]),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: 'ปิดรูปภาพ',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  '${_index + 1} / ${widget.photos.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
