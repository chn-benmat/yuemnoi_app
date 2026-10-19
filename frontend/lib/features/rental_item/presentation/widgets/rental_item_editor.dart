import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/models/pickup_location.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/theme/app_form_field_styles.dart';
import '../../../../core/utils/app_image_compressor.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/pickup_location_field.dart';
import '../../domain/entities/rental_item.dart';
import 'rental_category_dropdown_field.dart';
import 'rental_category_picker.dart';
import 'rental_item_form_value.dart';
import 'rental_item_photo_editor.dart';

class RentalItemEditor extends StatefulWidget {
  const RentalItemEditor({
    super.key,
    required this.onSubmit,
    this.initialValue = const RentalItemFormValue(),
    this.isEditing = false,
    this.isSaving = false,
    this.didSave = false,
    this.errorMessage,
  });

  final RentalItemFormValue initialValue;
  final ValueChanged<RentalItemFormValue> onSubmit;
  final bool isEditing;
  final bool isSaving;
  final bool didSave;
  final String? errorMessage;

  @override
  State<RentalItemEditor> createState() => _RentalItemEditorState();
}

class _RentalItemEditorState extends State<RentalItemEditor> {
  final _formKey = GlobalKey<FormState>();
  final _imageKey = GlobalKey();
  final _pickupKey = GlobalKey();
  final _scrollController = ScrollController();
  final _fieldKeys = List.generate(
    5,
    (_) => GlobalKey<FormFieldState<String>>(),
  );
  final _nameFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _priceFocus = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final List<RentalItemPhoto> _photos;
  late String? _category;
  late String? _rentalType;
  PickupLocation? _pickup;
  bool _showErrors = false;
  bool _picking = false;
  bool _showingConfirmation = false;
  bool _confirming = false;
  bool _allowExit = false;
  bool _askingToLeave = false;

  bool get _busy =>
      widget.isSaving || _picking || _confirming || _showingConfirmation;
  String get _prefix => widget.isEditing ? 'edit-item' : 'rental-item';

  bool get _dirty {
    final initial = widget.initialValue;
    return _name.text != initial.name ||
        _description.text != initial.description ||
        _price.text != initial.price ||
        _category != initial.category ||
        _rentalType != initial.rentalType ||
        _pickup != initial.pickupLocation ||
        !listEquals(_photos, initial.photos);
  }

  RentalItemFormValue get _value => RentalItemFormValue(
    name: _name.text.trim(),
    category: _category,
    description: _description.text.trim(),
    rentalType: _rentalType,
    price: _price.text.trim(),
    photos: List.unmodifiable(_photos),
    pickupLocation: _pickup,
  );

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _name = TextEditingController(text: initial.name);
    _description = TextEditingController(text: initial.description);
    _price = TextEditingController(text: initial.price);
    _photos = [...initial.photos];
    _category = initial.category;
    _rentalType = initial.rentalType;
    _pickup = initial.pickupLocation;
  }

  @override
  void didUpdateWidget(covariant RentalItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSaving && !widget.isSaving) _confirming = false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _scrollController.dispose();
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  Future<void> _requestBack() async {
    if (_busy || _askingToLeave) return;
    if (_dirty && !_allowExit) {
      _askingToLeave = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ออกโดยไม่บันทึก?'),
          content: const Text('ข้อมูลที่กรอกและรูปภาพที่เปลี่ยนจะหายไป'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ทิ้งการแก้ไข'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('กรอกต่อ'),
            ),
          ],
        ),
      );
      _askingToLeave = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppRoutes.pop(context);
    });
  }

  Future<void> _pickImages() async {
    if (_busy || _photos.length >= 5) return;
    setState(() => _picking = true);
    try {
      final permitted = await AppPermissionService.requestGalleryPermission(
        context,
      );
      if (!permitted || !mounted) return;
      final remaining = 5 - _photos.length;
      final selected = await ImagePicker().pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        limit: remaining,
      );
      if (!mounted || selected.isEmpty) return;
      final additions = <RentalItemPhoto>[];
      for (final image in selected.take(remaining)) {
        final compressed = await AppImageCompressor.compress(
          bytes: await image.readAsBytes(),
          fileName: image.name,
        );
        additions.add(
          RentalItemPhoto.local(
            RentalItemImage(
              bytes: compressed.bytes,
              fileName: compressed.fileName,
            ),
          ),
        );
      }
      if (mounted) setState(() => _photos.addAll(additions));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถเตรียมรูปภาพได้ กรุณาลองใหม่'),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_busy) return;
    setState(() {
      final photo = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, photo);
    });
  }

  Future<void> _chooseCategory(FormFieldState<String> field) async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => RentalCategoryPicker(
        selected: _category,
        options: [
          if (_category != null &&
              !RentalCategoryDropdownField.options.contains(_category))
            _category!,
          ...RentalCategoryDropdownField.options,
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _category = selected);
    field.didChange(selected);
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _showErrors = true);
    final valid = _formKey.currentState!.validate();
    if (!valid || _photos.isEmpty || _photos.length > 5) {
      final firstError = _photos.isEmpty || _photos.length > 5
          ? _imageKey.currentContext
          : _fieldKeys
                    .where((key) => key.currentState?.hasError == true)
                    .firstOrNull
                    ?.currentContext ??
                _pickupKey.currentContext;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && firstError != null && firstError.mounted) {
          Scrollable.ensureVisible(
            firstError,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            alignment: 0.15,
          );
        }
      });
      return;
    }
    final draft = _value;
    setState(() => _showingConfirmation = true);
    var answered = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        void answer(bool value) {
          if (answered) return;
          answered = true;
          Navigator.of(dialogContext).pop(value);
        }

        return AlertDialog(
          icon: Icon(
            widget.isEditing ? Icons.save_outlined : Icons.add_box_outlined,
            color: AppColors.primaryColor,
          ),
          title: Text(
            widget.isEditing
                ? 'ยืนยันการบันทึกการแก้ไข?'
                : 'ยืนยันการเพิ่มอุปกรณ์?',
          ),
          content: Text(
            widget.isEditing
                ? 'ต้องการบันทึกการเปลี่ยนแปลงของ “${draft.name}” ใช่ไหม?'
                : 'ต้องการเพิ่ม “${draft.name}” เพื่อเปิดให้เช่าใช่ไหม?',
          ),
          actions: [
            TextButton(
              key: const Key('rental-confirm-cancel'),
              onPressed: () => answer(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const Key('rental-confirm-submit'),
              onPressed: () => answer(true),
              child: const Text('ยืนยัน'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    setState(() => _showingConfirmation = false);
    if (confirmed != true) return;
    if (_busy) return;
    setState(() => _confirming = true);
    widget.onSubmit(draft);
  }

  Widget _label(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppFormFieldStyles.labelTextStyle),
      const SizedBox(height: 8),
      child,
    ],
  );

  InputDecoration _decoration(String hint) => AppFormFieldStyles.decoration(
    context,
    variant: AppFormFieldVariant.outlined,
  ).copyWith(hintText: hint);

  Widget _textField({
    required int index,
    required String id,
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focus,
    int? maxLength,
    int lines = 1,
  }) => KeyedSubtree(
    key: ValueKey('$_prefix-$id'),
    child: _label(
      label,
      TextFormField(
        key: _fieldKeys[index],
        controller: controller,
        focusNode: focus,
        style: AppFormFieldStyles.textStyle,
        maxLength: maxLength,
        maxLines: lines,
        minLines: lines,
        textInputAction: lines == 1
            ? TextInputAction.next
            : TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: _decoration(hint),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'กรุณาระบุ$label';
          if (maxLength != null && value.runes.length > maxLength)
            return '$labelยาวเกิน $maxLength ตัวอักษร';
          return null;
        },
      ),
    ),
  );

  Widget _section(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppFormFieldStyles.outlinedHintColor,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    ),
  );

  Widget get _separator => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Divider(height: 1, color: AppFormFieldStyles.outlinedDisabledColor),
  );

  Widget _form() => Form(
    key: _formKey,
    autovalidateMode: _showErrors
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled,
    child: ListView(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeyedSubtree(
              key: _imageKey,
              child: RentalItemPhotoEditor(
                key: ValueKey(
                  widget.isEditing ? 'edit-item-images' : 'add-rental-images',
                ),
                photos: _photos,
                isPicking: _picking,
                errorText: !_showErrors
                    ? null
                    : _photos.isEmpty
                    ? 'กรุณาเพิ่มรูปภาพอย่างน้อย 1 รูป'
                    : _photos.length > 5
                    ? 'เพิ่มรูปภาพได้ไม่เกิน 5 รูป'
                    : null,
                onAdd: _pickImages,
                onRemove: (index) => setState(() => _photos.removeAt(index)),
                onReorder: _reorder,
              ),
            ),
            _separator,
            _section(
              'ข้อมูลอุปกรณ์',
              'บอกให้ผู้เช่ารู้ว่าอุปกรณ์ของคุณมีอะไรน่าสนใจ',
            ),
            _textField(
              index: 0,
              id: 'name',
              label: 'ชื่ออุปกรณ์',
              hint: 'เช่น กล้อง Canon EOS R50 พร้อมเลนส์',
              controller: _name,
              focus: _nameFocus,
              maxLength: 150,
            ),
            const SizedBox(height: 10),
            _label(
              'หมวดหมู่',
              FormField<String>(
                key: _fieldKeys[1],
                initialValue: _category,
                validator: (value) =>
                    value == null ? 'กรุณาเลือกหมวดหมู่' : null,
                builder: (field) => InkWell(
                  key: ValueKey('$_prefix-category'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _chooseCategory(field),
                  child: InputDecorator(
                    decoration: _decoration('เลือกหมวดหมู่').copyWith(
                      errorText: field.errorText,
                      suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    child: Text(
                      _category ?? 'เลือกหมวดหมู่',
                      style: AppFormFieldStyles.textStyle.copyWith(
                        color: _category == null
                            ? AppFormFieldStyles.outlinedHintColor
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _textField(
              index: 2,
              id: 'description',
              label: 'คำอธิบาย',
              hint: 'สภาพอุปกรณ์ อุปกรณ์ที่ให้มาด้วย และสิ่งที่ผู้เช่าควรรู้',
              controller: _description,
              focus: _descriptionFocus,
              maxLength: 2000,
              lines: 4,
            ),
            _separator,
            _section(
              'ราคาและการให้เช่า',
              'เลือกหน่วยการเช่า แล้วกำหนดราคาต่อรอบ',
            ),
            _label(
              'ประเภทการให้เช่า',
              FormField<String>(
                key: _fieldKeys[3],
                initialValue: _rentalType,
                validator: (value) => value == null || value.isEmpty
                    ? 'กรุณาเลือกประเภทการให้เช่า'
                    : null,
                builder: (field) => Column(
                  key: ValueKey(
                    widget.isEditing
                        ? 'edit-item-rental-type'
                        : 'rental-type-field',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (final type in ['รายวัน', 'รายชั่วโมง'])
                            SizedBox(
                              width:
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      21
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 12) / 2,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _rentalType = type);
                                  field.didChange(type);
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  foregroundColor: _rentalType == type
                                      ? AppColors.primaryColor
                                      : AppFormFieldStyles.outlinedTextColor,
                                  backgroundColor: _rentalType == type
                                      ? AppFormFieldStyles.outlinedHoverColor
                                      : Colors.white,
                                  side: BorderSide(
                                    color: _rentalType == type
                                        ? AppColors.primaryColor
                                        : AppFormFieldStyles
                                              .outlinedBorderColor,
                                    width: _rentalType == type ? 1.5 : 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: Icon(
                                  type == 'รายวัน'
                                      ? Icons.calendar_today_outlined
                                      : Icons.schedule_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  type,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            KeyedSubtree(
              key: ValueKey('$_prefix-price'),
              child: _label(
                'ราคาให้เช่า',
                TextFormField(
                  key: _fieldKeys[4],
                  controller: _price,
                  focusNode: _priceFocus,
                  style: AppFormFieldStyles.textStyle.copyWith(
                    fontSize: 18,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: _decoration('0').copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsetsDirectional.only(start: 16, end: 12),
                      child: Align(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Text(
                          '฿',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppFormFieldStyles.outlinedHintColor,
                          ),
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 12,
                        end: 16,
                      ),
                      child: Align(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Text(
                          _rentalType == null ? 'บาท' : 'บาท / ${_value.unit}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppFormFieldStyles.outlinedHintColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  validator: (value) {
                    final price = int.tryParse(value?.trim() ?? '');
                    return price == null || price <= 0
                        ? 'กรุณาระบุราคาที่มากกว่า 0'
                        : null;
                  },
                ),
              ),
            ),
            _separator,
            _section(
              'การรับอุปกรณ์',
              'เลือกสถานที่ที่สะดวกสำหรับนัดรับและคืนอุปกรณ์',
            ),
            KeyedSubtree(
              key: _pickupKey,
              child: PickupLocationField(
                variant: AppFormFieldVariant.outlined,
                value: _pickup,
                enabled: !_busy,
                onChanged: (value) => setState(() => _pickup = value),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = widget.didSave;
    return PopScope<Object?>(
      canPop: saved || _allowExit || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: AppFormFieldStyles.outlinedTextColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          toolbarHeight: 64,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(
              height: 1,
              color: AppFormFieldStyles.outlinedDisabledColor,
            ),
          ),
          leading: IconButton(
            tooltip: 'ย้อนกลับ',
            onPressed: _busy ? null : _requestBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            widget.isEditing ? 'แก้ไขอุปกรณ์' : 'เพิ่มอุปกรณ์ให้เช่า',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Expanded(
                  child: AbsorbPointer(absorbing: _busy, child: _form()),
                ),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: AppFormFieldStyles.outlinedDisabledColor,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.errorMessage != null && !_busy)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              widget.errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        AppPrimaryButton(
                          key: ValueKey(
                            widget.isEditing
                                ? 'edit-item-submit'
                                : 'add-rental-submit',
                          ),
                          text: widget.isEditing
                              ? 'บันทึกการแก้ไข'
                              : 'เพิ่มอุปกรณ์',
                          borderRadius: 16,
                          isLoading: widget.isSaving || _confirming,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
