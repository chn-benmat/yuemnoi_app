import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';

class ChatImagePreviewModal extends StatefulWidget {
  const ChatImagePreviewModal({
    super.key,
    required this.images,
    required this.onSend,
    required this.onAddMore,
  });

  final List<XFile> images;
  final void Function(List<XFile> images, String caption) onSend;
  final Future<List<XFile>> Function() onAddMore;

  @override
  State<ChatImagePreviewModal> createState() => _ChatImagePreviewModalState();
}

class _ChatImagePreviewModalState extends State<ChatImagePreviewModal> {
  late List<XFile> _selectedImages;
  int _selectedIndex = 0;
  final TextEditingController _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedImages = List<XFile>.from(widget.images);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_selectedIndex >= _selectedImages.length) {
        _selectedIndex = (_selectedImages.length - 1).clamp(0, 9999);
      }
    });

    if (_selectedImages.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickMore() async {
    final more = await widget.onAddMore();
    if (more.isNotEmpty && mounted) {
      setState(() {
        _selectedImages.addAll(more);
      });
    }
  }

  void _handleSend() {
    if (_selectedImages.isEmpty) return;
    widget.onSend(_selectedImages, _captionController.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      height: MediaQuery.of(context).size.height * (isKeyboardOpen ? 0.85 : 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1B2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFFD8B4FE),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'ส่งรูปภาพ (${_selectedImages.length} รูป)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'ปิด',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Main Selected Image Preview
          Expanded(
            child: _selectedImages.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black38,
                        alignment: Alignment.center,
                        child: kIsWeb
                            ? Image.network(
                                _selectedImages[_selectedIndex].path,
                                fit: BoxFit.contain,
                              )
                            : Image.file(
                                File(_selectedImages[_selectedIndex].path),
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
          ),

          // Thumbnail selector strip
          Container(
            height: 76,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == _selectedImages.length) {
                  // Add more button
                  return InkWell(
                    onTap: _pickMore,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white24,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              color: Color(0xFFD8B4FE), size: 22),
                          SizedBox(height: 2),
                          Text(
                            'เพิ่มรูป',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final isCurrent = index == _selectedIndex;
                final file = _selectedImages[index];

                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _selectedIndex = index),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? AppColors.primaryColor
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: kIsWeb
                              ? Image.network(file.path, fit: BoxFit.cover)
                              : Image.file(File(file.path), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Caption Input and Send Button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'เพิ่มข้อความประกอบรูปภาพ (ไม่บังคับ)...',
                          hintStyle:
                              TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _selectedImages.isEmpty ? null : _handleSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ส่ง (${_selectedImages.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.send_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
