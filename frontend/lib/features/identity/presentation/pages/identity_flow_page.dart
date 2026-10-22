import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_form_field_styles.dart';
import '../../../../core/widgets/app_field_label.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../data/asset_thai_address_repository.dart';
import '../../domain/identity_repository.dart';
import '../../domain/thai_address.dart';
import '../identity_address_cubit.dart';
import '../identity_cubit.dart';
import '../widgets/identity_address_dropdown.dart';
import '../widgets/identity_camera_page.dart';
import '../widgets/identity_widgets.dart';

class IdentityPage extends StatefulWidget {
  const IdentityPage({
    super.key,
    this.capture = captureIdentityPhoto,
    this.addressRepository,
    this.selfieWithCard = false,
  });
  final IdentityCapture capture;
  final ThaiAddressRepository? addressRepository;
  final bool selfieWithCard;
  @override
  State<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends State<IdentityPage> {
  late final IdentityAddressCubit _addressCubit;
  final _form = GlobalKey<FormState>();
  final _birthField = GlobalKey<FormFieldState<String>>();
  final _birthDisplay = TextEditingController();
  final _firstName = TextEditingController(),
      _lastName = TextEditingController(),
      _id = TextEditingController(),
      _birth = TextEditingController(),
      _addressDetail = TextEditingController(),
      _postalCode = TextEditingController(),
      _province = TextEditingController(),
      _district = TextEditingController(),
      _subdistrict = TextEditingController();
  Uint8List? _card, _selfie;

  bool _consent = false,
      _confirmed = false,
      _capturing = false,
      _validateDetails = false,
      _allowExit = false,
      _consentPrompted = false,
      _consentDialogOpen = false;
  String? _namePrefix;
  static const _namePrefixes = ['นาย', 'นางสาว', 'นาง'];
  Map<String, TextEditingController> get _cardFields => {
    'first_name': _firstName,
    'last_name': _lastName,
    'citizen_id': _id,
    'birth_date': _birth,
    'address_detail': _addressDetail,
    'postal_code': _postalCode,
    'province': _province,
    'district': _district,
    'subdistrict': _subdistrict,
  };
  String get _legalName =>
      '$_namePrefix ${_firstName.text.trim()} ${_lastName.text.trim()}';
  late final Timer _clock;
  IdentityCubit get _cubit => context.read<IdentityCubit>();
  bool get _draft =>
      _card != null ||
      _selfie != null ||
      _namePrefix != null ||
      _cardFields.values.any((c) => c.text.isNotEmpty);
  @override
  void initState() {
    super.initState();
    _addressCubit = IdentityAddressCubit(
      widget.addressRepository ?? AssetThaiAddressRepository(),
    )..load();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _clearCardFields() {
    for (final c in _cardFields.values) {
      c.clear();
    }
    _birthDisplay.clear();
    _namePrefix = null;
    _confirmed = false;
  }

  void _clear() {
    _card = null;
    _selfie = null;
    _clearCardFields();
    _confirmed = false;
    _validateDetails = false;
    if (!_addressCubit.isClosed) _addressCubit.reset();
  }

  @override
  void dispose() {
    _clock.cancel();
    _addressCubit.close();
    _clear();
    for (final c in [..._cardFields.values, _birthDisplay]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_cubit.state.busy || _capturing) return;
    if (_draft) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ออกจากขั้นตอนนี้?'),
          content: const Text(
            'รูปและข้อมูลที่ยังไม่ส่งจะถูกล้าง เมื่อกลับมาต้องถ่ายและกรอกใหม่',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ทำต่อ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ออกและล้างข้อมูล'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _message(String text) => showAppPopup(context, content: Text(text));

  Future<void> _showConsent() async {
    if (_consentDialogOpen || !mounted) return;
    _consentDialogOpen = true;
    final previouslyAccepted = _consent;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: previouslyAccepted,
      builder: (_) =>
          IdentityConsentDialog(previouslyAccepted: previouslyAccepted),
    );
    _consentDialogOpen = false;
    if (!mounted || previouslyAccepted) return;
    if (agreed == true) {
      setState(() => _consent = true);
    } else {
      await _back();
    }
  }

  void _scheduleConsent(String kind) {
    if (kind != 'form' || _consent || _consentPrompted) return;
    _consentPrompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _kind(_cubit.state) == 'form') _showConsent();
    });
  }

  Future<bool> _prepareCapture() async {
    if (!_consent) {
      await _showConsent();
      if (!mounted || !_consent) return false;
    }
    if (!mounted) return false;
    FocusScope.of(context).unfocus();
    // ถ่ายเก็บไว้ในหน้านี้ก่อน และเริ่มคำขอกับเซิร์ฟเวอร์เมื่อกดส่ง
    return true;
  }

  Future<bool> _capture(IdentityCaptureKind kind) async {
    if (_capturing || _cubit.state.busy) return false;
    setState(() => _capturing = true);
    try {
      if (!await _prepareCapture()) {
        return false;
      }
      if (!mounted) return false;
      final bytes = await widget.capture(context, kind);
      if (!mounted || bytes == null) return false;
      if (bytes.length > 5 * 1024 * 1024) {
        _message('ภาพต้องไม่เกิน 5 MB');
        return false;
      }
      setState(() {
        if (kind == IdentityCaptureKind.card) {
          _card = bytes;
          // ถ่ายใหม่ยังเก็บข้อมูลที่กรอกไว้ แต่ต้องตรวจและยืนยันอีกครั้ง
          _confirmed = false;
        } else if (kind == IdentityCaptureKind.selfie ||
            kind == IdentityCaptureKind.selfieWithCard) {
          _selfie = bytes;
          _confirmed = false;
        }
      });
      return true;
    } catch (_) {
      if (mounted) _message('เปิดกล้องไม่สำเร็จ กรุณาลองใหม่');
      return false;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _capturePhotos() async {
    if (_capturing || _cubit.state.busy) return;
    if (_card == null && !await _capture(IdentityCaptureKind.card)) return;
    if (!mounted) return;
    if (_selfie == null &&
        !await _capture(
          widget.selfieWithCard
              ? IdentityCaptureKind.selfieWithCard
              : IdentityCaptureKind.selfie,
        ))
      return;
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณากรอกข้อมูลช่องนี้' : null;
  String? _postal(String? value) =>
      RegExp(r'^[1-9][0-9]{4}$').hasMatch(value?.trim() ?? '')
      ? null
      : 'กรุณากรอกรหัสไปรษณีย์ 5 หลักให้ถูกต้อง';

  Widget _cardTextField(
    String field,
    String label, {
    String? hintText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) => AppTextFormField(
    variant: AppFormFieldVariant.outlined,
    fieldKey: ValueKey(field),
    label: label,
    hintText: hintText,
    controller: _cardFields[field],
    validator: validator ?? _required,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    maxLines: maxLines,
    textInputAction: TextInputAction.next,
    onChanged: (_) => _invalidateConfirmation(),
  );

  void _invalidateConfirmation() {
    if (_confirmed) setState(() => _confirmed = false);
  }

  Widget _addressFields() {
    return BlocConsumer<IdentityAddressCubit, IdentityAddressState>(
      bloc: _addressCubit,
      listenWhen: (previous, current) =>
          previous.province != current.province ||
          previous.district != current.district ||
          previous.subdistrict != current.subdistrict,
      listener: (context, address) => setState(() {
        _province.text = address.province?.name ?? '';
        _district.text = address.district?.name ?? '';
        _subdistrict.text = address.subdistrict?.name ?? '';
        // เปลี่ยนพื้นที่แล้วล้างรหัสเดิม รวมถึงรหัสที่ผู้ใช้เคยแก้เอง
        _postalCode.text = address.postalCodes.isEmpty
            ? ''
            : address.postalCodes.first;
        _confirmed = false;
      }),
      builder: (context, address) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (address.error)
            Row(
              children: [
                const Expanded(child: Text('โหลดรายการที่อยู่ไม่สำเร็จ')),
                TextButton(
                  onPressed: _addressCubit.load,
                  child: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
          IdentityAddressDropdown<ThaiProvince>(
            fieldKey: const ValueKey('province'),
            label: 'จังหวัด',
            hintText: address.loading ? 'กำลังโหลดจังหวัด…' : 'เลือกจังหวัด',
            controller: _province,
            options: address.provinces,
            optionLabel: (province) => province.name,
            selected: address.province,
            onSelected: _addressCubit.selectProvince,
            validator: _required,
          ),
          const SizedBox(height: 20),
          IdentityAddressDropdown<ThaiDistrict>(
            fieldKey: const ValueKey('district'),
            label: 'อำเภอ/เขต',
            hintText: address.province == null
                ? 'เลือกจังหวัดก่อน'
                : 'เลือกอำเภอ/เขต',
            controller: _district,
            options: address.districts,
            optionLabel: (district) => district.name,
            selected: address.district,
            onSelected: _addressCubit.selectDistrict,
            validator: _required,
          ),
          const SizedBox(height: 20),
          IdentityAddressDropdown<ThaiSubdistrict>(
            fieldKey: const ValueKey('subdistrict'),
            label: 'ตำบล/แขวง',
            hintText: address.district == null
                ? 'เลือกอำเภอ/เขตก่อน'
                : 'เลือกตำบล/แขวง',
            controller: _subdistrict,
            options: address.subdistricts,
            optionLabel: (subdistrict) => subdistrict.name,
            selected: address.subdistrict,
            onSelected: _addressCubit.selectSubdistrict,
            validator: _required,
          ),
          const SizedBox(height: 20),
          _cardTextField(
            'postal_code',
            'รหัสไปรษณีย์',
            hintText: 'เติมอัตโนมัติ และแก้ไขได้',
            validator: _postal,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
          ),
          if (address.postalCodes.length > 1) ...[
            const SizedBox(height: 8),
            const Text(
              'พื้นที่นี้มีหลายรหัส เลือกให้ตรงกับที่อยู่ หรือแก้ไขรหัสด้านบน',
              style: TextStyle(fontSize: 12, color: IdentityColors.muted),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _postalCode,
              builder: (context, value, _) => Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final code in address.postalCodes)
                    ChoiceChip(
                      key: ValueKey('postal_option:$code'),
                      label: Text(code),
                      selected: value.text == code,
                      onSelected: (_) {
                        _postalCode.text = code;
                        _invalidateConfirmation();
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _validateDetails = true);
    final invalid = _form.currentState?.validateGranularly();
    if (invalid == null || invalid.isNotEmpty) {
      if (invalid?.isNotEmpty == true) {
        await Scrollable.ensureVisible(
          invalid!.first.context,
          alignment: 0.08,
          duration: const Duration(milliseconds: 220),
        );
      }
      return;
    }
    if (!_consent || !_confirmed || _card == null || _selfie == null) return;
    if (_addressCubit.state.subdistrict == null) return;
    final sent = await _cubit.submit(
      {
        'name_prefix': _namePrefix!,
        if (widget.selfieWithCard) 'selfie_with_card': 'true',
        'legal_name': _legalName,
        for (final field in _cardFields.entries)
          field.key: field.value.text.trim(),
      },
      _card!,
      _selfie!,
    );
    if (sent && mounted) setState(_clear);
  }

  String? _citizen(String? value) {
    final s = value?.trim() ?? '';
    return RegExp(r'^[0-9]{13}$').hasMatch(s)
        ? null
        : 'กรอกเลขบัตร 13 หลักให้ครบ';
  }

  String _dateText(String value) {
    final d = DateTime.tryParse(value);
    if (d == null) return 'เลือกวัน เดือน ปี';
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year + 543}';
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now().toUtc();
    final initial =
        DateTime.tryParse(_birth.text) ?? DateTime(now.year - 20, 1, 1);
    var year = initial.year, month = initial.month, day = initial.day;
    year = year.clamp(1, now.year);
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final days = DateTime(year, month + 1, 0).day;
          if (day > days) day = days;
          final date = DateTime(year, month, day);
          final validDate = !date.isAfter(DateUtils.dateOnly(now));
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'เลือกวันเกิด',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'แสดงปี พ.ศ. ตามบัตรประชาชน',
                    style: TextStyle(color: IdentityColors.muted),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth < 320 ||
                          MediaQuery.textScalerOf(context).scale(16) > 20;
                      final width = stacked
                          ? (constraints.maxWidth - 12) / 2
                          : (constraints.maxWidth - 24) / 3;
                      InputDecoration decoration(String label) =>
                          AppFormFieldStyles.decoration(
                            context,
                            variant: AppFormFieldVariant.outlined,
                          ).copyWith(
                            labelText: label,
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          );
                      return Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: width,
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('$year-$month-$days'),
                              initialValue: day,
                              isExpanded: true,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.merge(AppFormFieldStyles.textStyle),
                              decoration: decoration('วัน'),
                              items: [
                                for (var d = 1; d <= days; d++)
                                  DropdownMenuItem(value: d, child: Text('$d')),
                              ],
                              onChanged: (v) => setSheet(() => day = v!),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: DropdownButtonFormField<int>(
                              initialValue: month,
                              isExpanded: true,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.merge(AppFormFieldStyles.textStyle),
                              decoration: decoration('เดือน'),
                              items: [
                                for (var m = 1; m <= 12; m++)
                                  DropdownMenuItem(value: m, child: Text('$m')),
                              ],
                              onChanged: (v) => setSheet(() => month = v!),
                            ),
                          ),
                          SizedBox(
                            width: stacked ? constraints.maxWidth : width,
                            child: DropdownButtonFormField<int>(
                              initialValue: year,
                              isExpanded: true,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.merge(AppFormFieldStyles.textStyle),
                              decoration: decoration('ปี พ.ศ.'),
                              items: [
                                for (var y = now.year; y >= 1; y--)
                                  DropdownMenuItem(
                                    value: y,
                                    child: Text('${y + 543}'),
                                  ),
                              ],
                              onChanged: (v) => setSheet(() => year = v!),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (!validDate) ...[
                    const IdentityNotice(
                      'เลือกวันเกิดที่ไม่อยู่ในอนาคต',
                      error: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppPrimaryButton(
                    text: 'ใช้วันที่นี้',
                    onPressed: validDate
                        ? () => Navigator.pop(context, date)
                        : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _birth.text =
            '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
        _birthDisplay.text = _dateText(_birth.text);
        _confirmed = false;
      });
      _birthField.currentState?.didChange(_birthDisplay.text);
      _birthField.currentState?.validate();
    }
  }

  Widget _birthDateField() => AppTextFormField(
    key: const ValueKey('pick_birth_date'),
    fieldKey: _birthField,
    variant: AppFormFieldVariant.outlined,
    label: 'วันเกิดตามบัตรประชาชน',
    hintText: 'เลือกวัน เดือน ปี',
    controller: _birthDisplay,
    readOnly: true,
    enableInteractiveSelection: false,
    onTap: _pickBirthDate,
    suffixIcon: const Icon(
      Icons.calendar_month_outlined,
      size: 20,
      color: IdentityColors.primary,
    ),
    validator: (_) {
      final date = DateTime.tryParse(_birth.text);
      if (date == null) return 'กรุณาเลือกวันที่';
      final today = DateUtils.dateOnly(DateTime.now().toUtc());
      if (date.isAfter(today)) return 'วันเกิดต้องไม่อยู่ในอนาคต';
      if (!identityValidBirthDate(_birth.text)) {
        return 'กรุณาตรวจวันเกิดให้ถูกต้อง';
      }
      return null;
    },
  );
  Widget _photoPair() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: IdentityPhotoTile(
          key: const ValueKey('card_photo'),
          title: 'บัตรประชาชน',
          icon: Icons.badge_outlined,
          bytes: _card,
          onRetake: _capturing || _cubit.state.busy
              ? null
              : _card == null
              ? _capturePhotos
              : () => _capture(IdentityCaptureKind.card),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: IdentityPhotoTile(
          key: const ValueKey('selfie_photo'),
          title: widget.selfieWithCard ? 'รูปคู่บัตรประชาชน' : 'ใบหน้าของคุณ',
          icon: Icons.face_outlined,
          bytes: _selfie,
          onRetake: _capturing || _cubit.state.busy
              ? null
              : _selfie == null || _card == null
              ? _capturePhotos
              : () => _capture(
                  widget.selfieWithCard
                      ? IdentityCaptureKind.selfieWithCard
                      : IdentityCaptureKind.selfie,
                ),
        ),
      ),
    ],
  );

  Widget _details() => Form(
    key: _form,
    autovalidateMode: _validateDetails
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IdentityHeading(
          'ตรวจข้อมูล แล้วส่งคำขอ',
          'ถ่ายบัตรและใบหน้า แล้วกรอกข้อมูลตามบัตรประชาชนก่อนส่ง',
        ),
        const SizedBox(height: 24),
        _photoPair(),
        const SizedBox(height: 24),
        const IdentitySectionTitle(
          'ข้อมูลส่วนตัว',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 8),
        const Text(
          'กรอกให้ครบทุกช่อง',
          style: TextStyle(fontSize: 12, color: IdentityColors.muted),
        ),
        const SizedBox(height: 20),
        const AppFieldLabel(
          text: 'คำนำหน้าชื่อ',
          style: AppFormFieldStyles.labelTextStyle,
          padding: EdgeInsets.only(bottom: 8),
        ),
        FormField<String>(
          key: ValueKey('name_prefix:$_namePrefix'),
          initialValue: _namePrefix,
          validator: (value) => value == null ? 'กรุณาเลือกคำนำหน้าชื่อ' : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prefix in _namePrefixes)
                    ChoiceChip(
                      label: Text(prefix),
                      selected: _namePrefix == prefix,
                      selectedColor: IdentityColors.tint,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: _namePrefix == prefix
                            ? IdentityColors.primary
                            : IdentityColors.line,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() {
                        _namePrefix = prefix;
                        _confirmed = false;
                      }),
                    ),
                ],
              ),
              if (field.hasError)
                Text(
                  field.errorText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _cardTextField('first_name', 'ชื่อ', hintText: 'ชื่อตามบัตรประชาชน'),
        const SizedBox(height: 20),
        _cardTextField(
          'last_name',
          'นามสกุล',
          hintText: 'นามสกุลตามบัตรประชาชน',
        ),
        const SizedBox(height: 20),
        _cardTextField(
          'citizen_id',
          'เลขบัตรประชาชน 13 หลัก',
          validator: _citizen,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
        ),
        const SizedBox(height: 20),
        _birthDateField(),
        const SizedBox(height: 8),
        const Text(
          'ใช้ตรวจข้อมูลให้ตรงกับบัตรประชาชน',
          style: TextStyle(
            fontSize: 12,
            height: 1.7,
            color: IdentityColors.muted,
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 32, color: IdentityColors.line),
        const IdentitySectionTitle(
          'ที่อยู่ตามบัตรประชาชน',
          icon: Icons.home_outlined,
        ),
        const SizedBox(height: 8),
        _cardTextField(
          'address_detail',
          'รายละเอียดที่อยู่',
          hintText: 'บ้านเลขที่ หมู่ อาคาร ชั้น ซอย ถนน',
          keyboardType: TextInputType.streetAddress,
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        _addressFields(),
        const SizedBox(height: 24),
        IdentityPanel(
          color: IdentityColors.canvas,
          padding: 12,
          child: CheckboxListTile(
            key: const ValueKey('identity_confirmation'),
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            activeColor: IdentityColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: const Text(
              'ตรวจแล้ว ข้อมูลและรูปทั้งหมดเป็นของฉันและถูกต้อง',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _showConsent,
          icon: const Icon(Icons.privacy_tip_outlined, size: 18),
          label: const Text('เงื่อนไขการใช้ข้อมูล'),
        ),
        const SizedBox(height: 12),
        const Text(
          'เมื่อส่งแล้ว เจ้าหน้าที่จะตรวจคำขอของคุณ ติดตามผลได้ที่หน้านี้',
          style: TextStyle(
            fontSize: 12,
            height: 1.7,
            color: IdentityColors.muted,
          ),
        ),
      ],
    ),
  );

  Widget _summaryRow(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: IdentityColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: IdentityColors.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _status(IdentityStatus status, String kind) {
    final approved = kind == 'approved', pending = kind == 'pending';
    final title = switch (kind) {
      'approved' => 'ยืนยันตัวตนแล้ว',
      'pending' => 'รับคำขอของคุณแล้ว',
      'corrections' => 'แก้อีกนิด แล้วส่งใหม่',
      'rejected' => 'คำขอยังไม่ผ่าน',
      'suspended' => 'บัญชีถูกจำกัดการใช้งาน',
      'unavailable' => 'ยังเปิดยืนยันไม่ได้',
      _ => 'เริ่มยืนยันตัวตนใหม่',
    };
    final description = switch (kind) {
      'approved' =>
        status.canList
            ? 'คุณพร้อมลงสินค้าและรับการเช่าแล้ว'
            : 'ตัวตนของคุณผ่านแล้ว สามารถใช้งานตามสิทธิ์ของบัญชีได้',
      'pending' => 'เจ้าหน้าที่กำลังรอตรวจข้อมูล\nกลับมาเช็กสถานะที่หน้านี้ได้',
      'corrections' =>
        'อ่านคำแนะนำจากเจ้าหน้าที่ แล้วเริ่มถ่ายและส่งข้อมูลที่ถูกต้องอีกครั้ง',
      'rejected' => 'ตรวจเหตุผลจากเจ้าหน้าที่ก่อนเริ่มคำขอใหม่',
      'suspended' => 'กรุณาติดต่อผู้ดูแลเพื่อสอบถามรายละเอียด',
      'unavailable' =>
        'ระบบกำลังทดลองเฉพาะบัญชีที่ได้รับเชิญ กรุณากลับมาใหม่ภายหลัง',
      _ =>
        'รอบการยืนยันเดิมหมดอายุ\nเริ่มรอบใหม่เพื่อส่งข้อมูลให้เจ้าหน้าที่ตรวจ',
    };
    final icon = switch (kind) {
      'approved' => Icons.verified_rounded,
      'pending' => Icons.hourglass_top_rounded,
      'corrections' => Icons.edit_note_rounded,
      'rejected' || 'suspended' => Icons.error_outline_rounded,
      'expired' => Icons.schedule_rounded,
      _ => Icons.info_outline_rounded,
    };
    final color = switch (kind) {
      'approved' => IdentityColors.success,
      'corrections' || 'expired' => IdentityColors.warning,
      'rejected' || 'suspended' => IdentityColors.danger,
      _ => IdentityColors.primary,
    };
    final label = switch (kind) {
      'approved' => 'ตรวจสอบเรียบร้อย',
      'pending' => 'อยู่ระหว่างตรวจสอบ',
      'corrections' => 'ต้องแก้ไขข้อมูล',
      'rejected' => 'ตรวจไม่ผ่าน',
      'suspended' => 'จำกัดการใช้งาน',
      'expired' => 'ต้องยืนยันใหม่',
      _ => 'ยังไม่เปิดใช้งาน',
    };
    final reason = status.request['reason'] ?? status.request['review_reason'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        IdentityHeading(title, description),
        const SizedBox(height: 24),
        if (reason is String && reason.trim().isNotEmpty) ...[
          IdentityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'คำแนะนำจากเจ้าหน้าที่',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(reason, style: const TextStyle(fontSize: 14, height: 1.7)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (pending) ...[
          const IdentityPanel(
            child: Column(
              children: [
                IdentityTip(Icons.check_circle_outline, 'ส่งรูปและข้อมูลแล้ว'),
                IdentityTip(
                  Icons.person_search_outlined,
                  'รอเจ้าหน้าที่ตรวจสอบ',
                ),
                IdentityTip(
                  Icons.notifications_none_rounded,
                  'กลับมาเช็กผลการพิจารณาได้ที่นี่',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const IdentityNotice(
            'คำขอที่ค้างจะหมดอายุภายใน 7 วัน ระหว่างรอตรวจยังใช้แอปได้ตามปกติ แต่ยังปล่อยเช่าไม่ได้',
          ),
        ],
        if (approved) ...[
          IdentityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_summaryRow('สถานะ', 'ผ่านการอนุมัติ')],
            ),
          ),
        ],
      ],
    );
  }

  String _kind(IdentityState state) {
    final s = state.status;
    if (s == null) return 'loading';
    if ((s.data['control'] as Map?)?['suspended'] == true) return 'suspended';
    if (s.verified) return 'approved';
    final request = s.request;
    final status = request['status'];
    if (status == 'pending') {
      final deadline = DateTime.tryParse(request['deadline']?.toString() ?? '');
      return deadline?.isBefore(DateTime.now()) == true ? 'expired' : 'pending';
    }
    if (['rejected', 'corrections', 'expired'].contains(status)) {
      return status as String;
    }
    if (!s.available) return 'unavailable';
    return 'form';
  }

  ({String text, VoidCallback? action, String? helper}) _action(
    IdentityState state,
    String kind,
  ) {
    if (kind == 'form') {
      if (!_consent) {
        return (
          text: 'อ่านเงื่อนไขการใช้ข้อมูล',
          action: _showConsent,
          helper: 'ยินยอมก่อนถ่ายภาพและส่งข้อมูล',
        );
      }
      if (_card == null || _selfie == null) {
        return (
          text: _card == null ? 'ถ่ายบัตรและใบหน้า' : 'ถ่ายใบหน้า',
          action: _capturePhotos,
          helper: 'ใช้บัตรตัวจริง ถ่ายให้ชัดและไม่มีแสงสะท้อน',
        );
      }
      return (
        text: 'ส่งคำขอยืนยันตัวตน',
        action: _confirmed ? _submit : null,
        helper: _confirmed ? null : 'ตรวจรูป ข้อมูล และติ๊กยืนยันก่อนส่ง',
      );
    }
    if (kind == 'approved') {
      return (
        text: state.status!.canList ? 'ไปลงสินค้าให้เช่า' : 'กลับไปใช้งานแอป',
        action: () async {
          if (!state.status!.canList) {
            _back();
            return;
          }
          await AppRoutes.openAddRentalItem(context);
        },
        helper: null,
      );
    }
    if (kind == 'pending') {
      return (
        text: 'เช็กสถานะล่าสุด',
        action: _cubit.load,
        helper: 'ยังไม่ต้องส่งคำขอซ้ำ',
      );
    }
    if (['corrections', 'rejected', 'expired'].contains(kind)) {
      return (
        text: 'เริ่มยืนยันอีกครั้ง',
        action: () {
          setState(() {
            _clear();
            _consent = false;
            _consentPrompted = false;
          });
          _cubit.resetCapture();
        },
        helper: null,
      );
    }
    return (text: 'โหลดสถานะใหม่', action: _cubit.load, helper: null);
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<IdentityCubit, IdentityState>(
        builder: (context, state) {
          final kind = _kind(state), action = _action(state, kind);
          _scheduleConsent(kind);
          return PopScope(
            canPop: _allowExit,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _back();
            },
            child: Scaffold(
              backgroundColor: IdentityColors.canvas,
              appBar: AppBar(
                backgroundColor: IdentityColors.canvas,
                surfaceTintColor: IdentityColors.canvas,
                title: const Text(
                  'ยืนยันตัวตน',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: IdentityColors.ink,
                  ),
                ),
                centerTitle: true,
                leading: IconButton(
                  tooltip: 'ย้อนกลับ',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              body: AbsorbPointer(
                absorbing: state.busy || _capturing,
                child: ResponsivePageBody(
                  key: ValueKey(kind),
                  verticalPadding: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.busy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: LinearProgressIndicator(
                            color: IdentityColors.primary,
                          ),
                        ),
                      if (state.error != null) ...[
                        IdentityNotice(state.error!, error: true),
                        const SizedBox(height: 20),
                      ],
                      if (kind == 'loading')
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(
                            child: Text(
                              'กำลังโหลดสถานะของคุณ…',
                              style: TextStyle(color: IdentityColors.muted),
                            ),
                          ),
                        )
                      else if (kind == 'form')
                        _details()
                      else
                        _status(state.status!, kind),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: IdentityColors.line)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (action.helper != null) ...[
                        Text(
                          action.helper!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: IdentityColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: AppPrimaryButton(
                          text: action.text,
                          isLoading: state.busy || _capturing,
                          onPressed: kind == 'loading' ? null : action.action,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
