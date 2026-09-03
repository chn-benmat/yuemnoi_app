import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/utils/app_image_compressor.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../domain/entities/rental_item.dart';
import '../bloc/rental_item_bloc.dart';
import '../bloc/rental_item_event.dart';
import '../bloc/rental_item_state.dart';
import '../widgets/rental_category_dropdown_field.dart';
import '../widgets/rental_item_image_picker.dart';
import '../widgets/rental_type_dropdown_field.dart';

class AddRentalItemScreen extends StatefulWidget {
  const AddRentalItemScreen({super.key});

  @override
  State<AddRentalItemScreen> createState() => _AddRentalItemScreenState();
}

class _AddRentalItemScreenState extends State<AddRentalItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _picker = ImagePicker();
  String? _category;
  String? _rentalType;
  bool _showImageValidationError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImages(int currentCount) async {
    final remaining = RentalItemBloc.maxImages - currentCount;
    if (remaining <= 0) return;

    final hasPermission = await AppPermissionService.requestGalleryPermission(
      context,
    );
    if (!hasPermission || !mounted) return;

    try {
      final selected = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        limit: remaining,
      );
      if (!mounted || selected.isEmpty) return;

      final images = <RentalItemImage>[];
      for (final image in selected) {
        final compressed = await AppImageCompressor.compress(
          bytes: await image.readAsBytes(),
          fileName: image.name,
        );
        images.add(
          RentalItemImage(
            bytes: compressed.bytes,
            fileName: compressed.fileName,
          ),
        );
      }
      if (mounted) {
        context.read<RentalItemBloc>().add(RentalItemImagesAdded(images));
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

  void _submit(RentalItemState state) {
    final isFormValid = _formKey.currentState!.validate();
    final imageError = _validateImages(state.images);
    if (!isFormValid || _rentalType == null || imageError != null) {
      setState(() => _showImageValidationError = imageError != null);
      return;
    }
    context.read<RentalItemBloc>().add(
      RentalItemSubmitted(
        RentalItemDraft(
          name: _nameController.text,
          category: _category!,
          description: _descriptionController.text,
          rentalType: _rentalType!,
          price: int.parse(_priceController.text),
          images: state.images,
        ),
      ),
    );
  }

  String? _validateRequired(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'กรุณาระบุ$label' : null;

  String? _validateImages(List<RentalItemImage> images) {
    if (images.length < RentalItemBloc.minImages) {
      return 'กรุณาเพิ่มรูปภาพอย่างน้อย ${RentalItemBloc.minImages} รูป';
    }
    if (images.length > RentalItemBloc.maxImages) {
      return 'เพิ่มรูปภาพได้ไม่เกิน ${RentalItemBloc.maxImages} รูป';
    }
    return null;
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
          'เพิ่มอุปกรณ์ให้เช่า',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: BlocConsumer<RentalItemBloc, RentalItemState>(
        listener: (context, state) {
          if (state.status == RentalItemSubmissionStatus.failure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage ?? 'เพิ่มอุปกรณ์ไม่สำเร็จ'),
                ),
              );
          }
          if (state.status == RentalItemSubmissionStatus.success) {
            AppRoutes.pop(context, state.createdItem);
          }
        },
        builder: (context, state) => Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                  children: [
                    RentalItemImagePicker(
                      images: state.images,
                      maxImages: RentalItemBloc.maxImages,
                      errorText: _showImageValidationError
                          ? _validateImages(state.images)
                          : null,
                      onAdd: () => _pickImages(state.images.length),
                      onRemove: (index) => context.read<RentalItemBloc>().add(
                        RentalItemImageRemoved(index),
                      ),
                    ),
                    const SizedBox(height: 22),
                    AppTextFormField(
                      fieldKey: const Key('rental-item-name'),
                      label: 'ชื่ออุปกรณ์',
                      hintText: "กรุณาระบุชื่ออุปกรณ์",
                      controller: _nameController,
                      validator: (value) =>
                          _validateRequired(value, 'ชื่ออุปกรณ์'),
                    ),
                    const SizedBox(height: 12),
                    RentalCategoryDropdownField(
                      value: _category,
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 12),
                    AppTextFormField(
                      fieldKey: const Key('rental-item-description'),
                      label: 'คำอธิบาย',
                      hintText: "กรุณาระบุคำอธิบาย",
                      controller: _descriptionController,
                      maxLines: 4,
                      minLines: 4,
                      validator: (value) =>
                          _validateRequired(value, 'คำอธิบาย'),
                    ),
                    const SizedBox(height: 12),
                    RentalTypeDropdownField(
                      value: _rentalType,
                      onChanged: (value) => setState(() => _rentalType = value),
                    ),
                    const SizedBox(height: 12),
                    AppTextFormField(
                      fieldKey: const Key('rental-item-price'),
                      label: 'ราคา',
                      hintText: '0',
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
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                child: AppPrimaryButton(
                  key: const Key('add-rental-submit'),
                  text: 'เพิ่ม',
                  isLoading:
                      state.status == RentalItemSubmissionStatus.submitting,
                  onPressed: () => _submit(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
