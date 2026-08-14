import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/app_image_compressor.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../../rental_item/domain/entities/rental_item.dart';
import '../../../rental_item/presentation/widgets/rental_category_dropdown_field.dart';
import '../../../rental_item/presentation/widgets/rental_item_dropdown_field.dart';
import '../../domain/entities/item_detail.dart';
import '../bloc/item_detail_bloc.dart';
import '../bloc/item_detail_event.dart';
import '../bloc/item_detail_state.dart';

class EditItemScreen extends StatefulWidget {
  const EditItemScreen({super.key, required this.item});

  final ItemDetail item;

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late String _category;
  late String _rentalType;
  late List<_EditableImage> _images;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item.name);
    _descriptionController = TextEditingController(text: item.description);
    _priceController = TextEditingController(text: item.price.toString());
    _category = item.category;
    _rentalType = item.rentalType;
    _images = item.imageUrls
        .map((url) => _EditableImage.remote(url))
        .toList(growable: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = 5 - _images.length;
    if (remaining <= 0) return;
    try {
      final selected = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        limit: remaining,
      );
      if (!mounted || selected.isEmpty) return;
      final additions = <_EditableImage>[];
      for (final image in selected) {
        final compressed = await AppImageCompressor.compress(
          bytes: await image.readAsBytes(),
          fileName: image.name,
        );
        additions.add(
          _EditableImage.local(
            RentalItemImage(
              bytes: compressed.bytes,
              fileName: compressed.fileName,
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _images.addAll(additions.take(remaining));
          _imageError = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('ไม่สามารถประมวลผลรูปภาพได้')),
        );
    }
  }

  void _submit() {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (_images.isEmpty) {
      setState(() => _imageError = 'กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป');
      return;
    }
    if (!formValid) return;

    context.read<ItemDetailBloc>().add(
      ItemDetailUpdateSubmitted(
        ItemEditDraft(
          itemId: widget.item.id,
          name: _nameController.text,
          category: _category,
          description: _descriptionController.text,
          rentalType: _rentalType,
          price: int.parse(_priceController.text),
          retainedImageUrls: _images
              .where((image) => image.remoteUrl != null)
              .map((image) => image.remoteUrl!)
              .toList(growable: false),
          newImages: _images
              .where((image) => image.localImage != null)
              .map((image) => image.localImage!)
              .toList(growable: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          tooltip: 'ย้อนกลับ',
          onPressed: () => AppRoutes.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 30),
        ),
        title: const Text(
          'แก้ไขอุปกรณ์ให้เช่า',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: BlocConsumer<ItemDetailBloc, ItemDetailState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.status == ItemDetailStatus.failure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage ?? 'แก้ไขอุปกรณ์ไม่สำเร็จ'),
                ),
              );
          } else if (state.status == ItemDetailStatus.loaded &&
              state.item != widget.item) {
            AppRoutes.pop(context, true);
          }
        },
        builder: (context, state) {
          final categoryOptions = [
            if (!RentalCategoryDropdownField.options.contains(_category))
              _category,
            ...RentalCategoryDropdownField.options,
          ];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
              children: [
                _EditableImagePicker(
                  images: _images,
                  errorText: _imageError,
                  onAdd: _pickImages,
                  onRemove: (index) => setState(() {
                    _images.removeAt(index);
                    _imageError = _images.isEmpty
                        ? 'กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป'
                        : null;
                  }),
                ),
                const SizedBox(height: 22),
                AppTextFormField(
                  fieldKey: const Key('edit-item-name'),
                  label: 'ชื่ออุปกรณ์',
                  controller: _nameController,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'กรุณาระบุชื่ออุปกรณ์'
                      : null,
                ),
                const SizedBox(height: 12),
                RentalItemDropdownField(
                  fieldKey: const Key('edit-item-category'),
                  label: 'หมวดหมู่',
                  hintText: 'เลือกหมวดหมู่',
                  options: categoryOptions,
                  value: _category,
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                  validator: (value) =>
                      value == null ? 'กรุณาเลือกหมวดหมู่' : null,
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  fieldKey: const Key('edit-item-description'),
                  label: 'คำอธิบาย',
                  controller: _descriptionController,
                  maxLines: 4,
                  minLines: 4,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'กรุณาระบุคำอธิบาย'
                      : null,
                ),
                const SizedBox(height: 12),
                RentalItemDropdownField(
                  fieldKey: const Key('edit-item-rental-type'),
                  label: 'ประเภทการให้เช่า',
                  hintText: 'เลือกประเภทการให้เช่า',
                  options: const ['รายวัน', 'รายชั่วโมง'],
                  value: _rentalType,
                  onChanged: (value) {
                    if (value != null) setState(() => _rentalType = value);
                  },
                  validator: (value) =>
                      value == null ? 'กรุณาเลือกประเภทการให้เช่า' : null,
                ),
                const SizedBox(height: 12),
                AppTextFormField(
                  fieldKey: const Key('edit-item-price'),
                  label: 'ราคา',
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  prefix: const Text(
                    '฿',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.labelColor,
                    ),
                  ),
                  validator: (value) {
                    final price = int.tryParse(value?.trim() ?? '');
                    return price == null || price <= 0
                        ? 'กรุณาระบุราคาที่มากกว่า 0'
                        : null;
                  },
                ),
                const SizedBox(height: 48),
                AppPrimaryButton(
                  text: 'บันทึก',
                  isLoading: state.status == ItemDetailStatus.updating,
                  onPressed: _submit,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EditableImage {
  const _EditableImage._({this.remoteUrl, this.localImage});

  factory _EditableImage.remote(String url) => _EditableImage._(remoteUrl: url);

  factory _EditableImage.local(RentalItemImage image) =>
      _EditableImage._(localImage: image);

  final String? remoteUrl;
  final RentalItemImage? localImage;
}

class _EditableImagePicker extends StatelessWidget {
  const _EditableImagePicker({
    required this.images,
    required this.errorText,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_EditableImage> images;
  final String? errorText;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'รูปภาพ',
                style: TextStyle(color: AppColors.labelColor, fontSize: 14),
              ),
            ),
            Text(
              '${images.length} / 5',
              style: const TextStyle(
                color: AppColors.primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length + (images.length < 5 ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == images.length) {
                return InkWell(
                  key: const Key('edit-item-add-image'),
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 126,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F2),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFD8DADC),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          backgroundColor: Color(0xFFE7D5F7),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: AppColors.primaryColor,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'เพิ่มรูป',
                          style: TextStyle(color: Color(0xFF626267)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final image = images[index];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SizedBox.square(
                      dimension: 126,
                      child: image.remoteUrl != null
                          ? CachedNetworkImage(
                              imageUrl: image.remoteUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  const ColoredBox(
                                    color: Color(0xFFE9E9EC),
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                            )
                          : Image.memory(
                              Uint8List.fromList(image.localImage!.bytes),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  Positioned(
                    top: -5,
                    right: -5,
                    child: IconButton.filled(
                      key: ValueKey('edit-item-remove-image-$index'),
                      onPressed: () => onRemove(index),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.65),
                        minimumSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
