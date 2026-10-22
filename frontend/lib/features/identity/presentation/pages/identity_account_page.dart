import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_form_field_styles.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../data/asset_thai_address_repository.dart';
import '../../data/camera_file_cleanup.dart';
import '../../domain/identity_account_repository.dart';
import '../../domain/identity_repository.dart';
import '../../domain/thai_address.dart';
import '../identity_account_cubit.dart';
import '../identity_address_cubit.dart';
import '../widgets/identity_address_dropdown.dart';
import '../widgets/identity_camera_page.dart';
import '../widgets/identity_widgets.dart';
import '../widgets/identity_account_loading.dart';

class IdentityAccountPage extends StatefulWidget {
  const IdentityAccountPage({
    super.key,
    this.capture = captureIdentityPhoto,
    this.addressRepository,
  });
  final IdentityCapture capture;
  final ThaiAddressRepository? addressRepository;
  @override
  State<IdentityAccountPage> createState() => _IdentityAccountPageState();
}

class _IdentityAccountPageState extends State<IdentityAccountPage> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final name in [
      'name_prefix',
      'first_name',
      'last_name',
      'citizen_id',
      'birth_date',
      'address_detail',
      'postal_code',
      'province',
      'district',
      'subdistrict',
    ])
      name: TextEditingController(),
  };
  final _birthDisplay = TextEditingController();
  late final IdentityAddressCubit _address;
  IdentityAccountDetails? _loaded;
  Map<String, String> _original = {};
  Uint8List? _card, _selfie;
  bool _allowExit = false, _capturing = false, _dialogOpen = false;
  bool _removedCard = false, _removedSelfie = false;
  bool _consent = false;
  Uint8List? _photoBytes(IdentityAccountState state, bool selfie) => selfie
      ? (_removedSelfie ? null : _selfie ?? state.photos['selfie'])
      : (_removedCard ? null : _card ?? state.photos['card']);
  IdentityAccountCubit get _cubit => context.read<IdentityAccountCubit>();
  bool get _readOnly =>
      _cubit.state.sent ||
      _cubit.state.details?.pending == true ||
      _cubit.state.details?.status.restricted == true;
  bool get _dirty =>
      _removedCard ||
      _removedSelfie ||
      _card != null ||
      _selfie != null ||
      _fields.entries.any((e) => e.value.text != (_original[e.key] ?? ''));

  @override
  void initState() {
    super.initState();
    _address = IdentityAddressCubit(
      widget.addressRepository ?? AssetThaiAddressRepository(),
    );
    _address.load().then((_) {
      if (mounted) _restoreAddress();
    });
  }

  @override
  void dispose() {
    _address.close();
    for (final field in _fields.values) {
      field.dispose();
    }
    _birthDisplay.dispose();
    _card = _selfie = null;
    super.dispose();
  }

  void _hydrate(IdentityAccountDetails details) {
    _loaded = details;
    for (final entry in _fields.entries) {
      entry.value.text = details.fields[entry.key] ?? '';
    }
    final birth = DateTime.tryParse(_fields['birth_date']!.text);
    _birthDisplay.text = birth == null
        ? ''
        : '${birth.day.toString().padLeft(2, '0')}/${birth.month.toString().padLeft(2, '0')}/${birth.year}';
    _original = {for (final e in _fields.entries) e.key: e.value.text};
    _restoreAddress();
  }

  void _restoreAddress() => _address.restore(
    _fields['province']!.text,
    _fields['district']!.text,
    _fields['subdistrict']!.text,
  );

  void _message(String text) => showAppPopup(context, content: Text(text));

  Future<bool> _confirm(
    String title,
    String body,
    String cancel,
    String confirm,
  ) async {
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    return result == true;
  }

  Future<void> _back() async {
    if ((_cubit.state.busy && !_cubit.state.loading) ||
        _capturing ||
        _dialogOpen)
      return;
    if (_dirty &&
        !_cubit.state.sent &&
        !await _confirm(
          'ออกโดยไม่บันทึกการแก้ไข?',
          'ข้อมูลที่แก้ไขจะยังไม่ถูกส่งให้เจ้าหน้าที่ตรวจสอบ',
          'แก้ไขต่อ',
          'ออกโดยไม่บันทึก',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        AppRoutes.goToProfile(context);
      }
    });
  }

  Future<void> _photo(bool selfie) async {
    if (_capturing || _cubit.state.busy) return;
    if (_loaded?.hasIdentity != true && !_consent) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (_) => const IdentityConsentDialog(previouslyAccepted: false),
      );
      if (!mounted || agreed != true) return;
      _consent = true;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _capturing = true);
    try {
      var gallery = false;
      if (!selfie) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('ถ่ายรูปบัตร'),
                  onTap: () => Navigator.pop(sheet, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('เลือกจากแกลเลอรี'),
                  onTap: () => Navigator.pop(sheet, 'gallery'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null) return;
        gallery = choice == 'gallery';
      }
      Uint8List? bytes;
      if (gallery) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 90,
        );
        if (file != null) {
          try {
            bytes = await file.readAsBytes();
          } finally {
            await clearCameraFile(file.path);
          }
        }
      } else {
        if (!mounted) return;
        bytes = await widget.capture(
          context,
          selfie
              ? IdentityCaptureKind.selfieWithCard
              : IdentityCaptureKind.card,
        );
      }
      if (!mounted || bytes == null) return;
      if (bytes.length > 5 * 1024 * 1024) {
        _message('ภาพต้องไม่เกิน 5 MB');
        return;
      }
      setState(() {
        if (selfie) {
          _selfie = bytes;
          _removedSelfie = false;
        } else {
          _card = bytes;
          _removedCard = false;
        }
      });
    } catch (_) {
      if (mounted) _message('เปิดรูปไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _birth() async {
    final now = DateTime.now();
    final saved = DateTime.tryParse(_fields['birth_date']!.text);
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('en', 'US'),
      helpText: 'วันเกิด (ปี ค.ศ.)',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือก',
      initialDate: saved != null && !saved.isAfter(now)
          ? saved
          : DateTime(now.year - 20),
      firstDate: DateTime(1),
      lastDate: now,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _fields['birth_date']!.text =
          '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
      _birthDisplay.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
    });
  }

  Future<void> _save(IdentityAccountState state) async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      _message('กรุณาตรวจข้อมูลให้ครบถ้วน');
      return;
    }
    if (_photoBytes(state, false) == null || _photoBytes(state, true) == null) {
      _message('กรุณาเพิ่มรูปบัตรและรูปคู่บัตรประชาชนให้ครบ');
      return;
    }
    if (!state.details!.hasIdentity && !_consent) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (_) => const IdentityConsentDialog(previouslyAccepted: false),
      );
      if (!mounted || agreed != true) return;
    }
    if (!await _confirm(
      'ส่งข้อมูลให้เจ้าหน้าที่ตรวจสอบ?',
      'ข้อมูลใหม่จะมีผลเมื่อได้รับอนุมัติ ระหว่างรอตรวจสอบคุณยังใช้ข้อมูลและสิทธิ์เดิมได้ตามปกติ',
      'กลับไปแก้ไข',
      'ยืนยันส่งข้อมูล',
    )) {
      return;
    }
    if (!mounted) return;
    final fields = {
      for (final e in _fields.entries) e.key: e.value.text.trim(),
      if (_card == null && state.details!.evidence['card'] != null)
        'card_evidence_id': state.details!.evidence['card']!,
      if (_selfie == null && state.details!.evidence['selfie'] != null)
        'selfie_evidence_id': state.details!.evidence['selfie']!,
    };
    fields['legal_name'] =
        '${fields['name_prefix']} ${fields['first_name']} ${fields['last_name']}';
    final sent = await _cubit.submit(fields, card: _card, selfie: _selfie);
    if (!mounted || !sent) return;
    setState(() {
      _original = {for (final e in _fields.entries) e.key: e.value.text};
      _card = _selfie = null;
      _removedCard = _removedSelfie = false;
    });
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(
          Icons.task_alt_rounded,
          color: IdentityColors.success,
          size: 44,
        ),
        title: const Text('ส่งข้อมูลแล้ว'),
        content: const Text(
          'เจ้าหน้าที่จะตรวจสอบข้อมูลของคุณ\nติดตามผลได้ที่หน้านี้',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('เข้าใจแล้ว'),
          ),
        ],
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณากรอกข้อมูลช่องนี้' : null;

  Widget _text(
    String field,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: AppTextFormField(
      variant: AppFormFieldVariant.outlined,
      fieldKey: ValueKey(field),
      label: label,
      controller: _fields[field],
      readOnly: _readOnly,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: formatters,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      validator: (value) {
        if (_required(value) != null) return _required(value);
        if (field == 'postal_code' &&
            !RegExp(r'^[1-9][0-9]{4}$').hasMatch(value!.trim()))
          return 'กรอกรหัสไปรษณีย์ 5 หลัก';
        final limit = field == 'address_detail' ? 500 : 150;
        if (value!.trim().runes.length > limit)
          return 'กรอกไม่เกิน $limit ตัวอักษร';
        return null;
      },
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _section(String title, String subtitle, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: IdentityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: IdentityColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: IdentityColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );

  Widget _citizenField() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('เลขบัตรประชาชน', style: AppFormFieldStyles.labelTextStyle),
        if (_loaded?.hasIdentity == true)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => AppRoutes.openContact(context),
              icon: const Icon(Icons.support_agent_rounded, size: 16),
              label: const Text(
                'เปลี่ยนเลขบัตร กรุณาติดต่อเจ้าหน้าที่',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        const SizedBox(height: 4),
        TextFormField(
          key: const ValueKey('citizen_id'),
          controller: _fields['citizen_id'],
          readOnly: _readOnly || _loaded?.hasIdentity == true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (_loaded?.hasIdentity == true) return null;
            if (value == null || !RegExp(r'^\d{13}$').hasMatch(value))
              return 'กรุณากรอกเลขบัตรประชาชน 13 หลัก';
            return null;
          },
          style: AppFormFieldStyles.textStyle,
          decoration:
              AppFormFieldStyles.decoration(
                context,
                variant: AppFormFieldVariant.outlined,
              ).copyWith(
                suffixIcon: _loaded?.hasIdentity == true
                    ? const Icon(Icons.lock_outline_rounded, size: 18)
                    : null,
              ),
        ),
      ],
    ),
  );

  Widget _addressFields() =>
      BlocBuilder<IdentityAddressCubit, IdentityAddressState>(
        bloc: _address,
        builder: (context, address) {
          Widget dropdown<T>(
            String name,
            String label,
            List<T> options,
            String Function(T) labelOf,
            ValueChanged<T> select,
            T? selected,
          ) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: IdentityAddressDropdown<T>(
              fieldKey: ValueKey(name),
              label: label,
              hintText: address.loading ? 'กำลังโหลด…' : 'เลือก$label',
              controller: _fields[name]!,
              options: options,
              optionLabel: labelOf,
              selected: selected,
              validator: _required,
              enabled: !_readOnly,
              onSelected: select,
            ),
          );
          return Column(
            children: [
              _text('address_detail', 'รายละเอียดที่อยู่', maxLines: 3),
              if (address.error)
                Row(
                  children: [
                    const Expanded(child: Text('โหลดรายการที่อยู่ไม่สำเร็จ')),
                    TextButton(
                      onPressed: _address.load,
                      child: const Text('ลองอีกครั้ง'),
                    ),
                  ],
                ),
              dropdown<ThaiProvince>(
                'province',
                'จังหวัด',
                address.provinces,
                (p) => p.name,
                (p) {
                  _address.selectProvince(p);
                  setState(() {
                    _fields['province']!.text = p.name;
                    _fields['district']!.clear();
                    _fields['subdistrict']!.clear();
                    _fields['postal_code']!.clear();
                  });
                },
                address.province,
              ),
              dropdown<ThaiDistrict>(
                'district',
                'อำเภอ/เขต',
                address.districts,
                (d) => d.name,
                (d) {
                  _address.selectDistrict(d);
                  setState(() {
                    _fields['district']!.text = d.name;
                    _fields['subdistrict']!.clear();
                    _fields['postal_code']!.clear();
                  });
                },
                address.district,
              ),
              dropdown<ThaiSubdistrict>(
                'subdistrict',
                'ตำบล/แขวง',
                address.subdistricts,
                (s) => s.name,
                (s) {
                  _address.selectSubdistrict(s);
                  setState(() {
                    _fields['subdistrict']!.text = s.name;
                    _fields['postal_code']!.text =
                        s.postalCodes.firstOrNull ?? '';
                  });
                },
                address.subdistrict,
              ),
              _text(
                'postal_code',
                'รหัสไปรษณีย์',
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
              ),
            ],
          );
        },
      );

  Widget _photoTile(
    String title,
    String subtitle,
    Uint8List? photo,
    bool selfie,
    bool editable,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: IdentityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: IdentityColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: IdentityColors.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: selfie ? 4 / 3 : 1.586,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: photo == null
                        ? IdentityColors.canvas
                        : const Color(0xFF29313C),
                    child: photo == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selfie
                                    ? Icons.contact_emergency_outlined
                                    : Icons.badge_outlined,
                                size: 48,
                                color: IdentityColors.primary,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'ยังไม่มีรูป',
                                style: TextStyle(color: IdentityColors.muted),
                              ),
                            ],
                          )
                        : InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (dialog) => Dialog(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: InteractiveViewer(
                                        child: Image.memory(
                                          photo,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialog),
                                      child: const Text('ปิด'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Image.memory(
                              photo,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                  if (photo != null && editable)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filled(
                        tooltip: selfie ? 'นำรูปคู่บัตรออก' : 'นำรูปบัตรออก',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xB3000000),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _capturing
                            ? null
                            : () => setState(() {
                                if (selfie) {
                                  _selfie = null;
                                  _removedSelfie = true;
                                } else {
                                  _card = null;
                                  _removedCard = true;
                                }
                              }),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (editable) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _capturing ? null : () => _photo(selfie),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                photo == null
                    ? Icons.add_a_photo_outlined
                    : Icons.photo_camera_outlined,
                size: 18,
              ),
              label: Text(photo == null ? 'เพิ่มรูป' : 'เปลี่ยนรูป'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _content(IdentityAccountState state) {
    final details = state.details!;
    final pending = details.pending || state.sent;
    final editable = !pending && !details.status.restricted;
    final requestStatus = details.status.request['status'];
    final reason = details.status.request['reason']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0E3FF), Color(0xFFFAF5FF)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    pending ? Icons.schedule_rounded : Icons.verified_rounded,
                    color: IdentityColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pending
                          ? 'รอตรวจสอบ'
                          : details.status.verified
                          ? 'ยืนยันตัวตนแล้ว'
                          : 'ยืนยันตัวตนด้วยบัตรประชาชน',
                      style: const TextStyle(
                        color: IdentityColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                pending ? 'ส่งแล้ว รออีกนิดนะ' : 'ข้อมูลของคุณ ดูแลได้ง่าย ๆ',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: IdentityColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pending
                    ? 'ดูข้อมูลที่ส่งได้ที่นี่ ข้อมูลใหม่จะมีผลเมื่อเจ้าหน้าที่อนุมัติ ระหว่างนี้ยังใช้ข้อมูลและสิทธิ์เดิมได้ตามปกติ'
                    : 'อัปเดตข้อมูลให้ตรงกับบัตรประชาชน\nทุกการแก้ไขจะได้รับการตรวจสอบโดยเจ้าหน้าที่',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: IdentityColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (details.status.restricted)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: IdentityNotice(
              'บัญชีถูกระงับการทำรายการ กรุณาติดต่อเจ้าหน้าที่',
              error: true,
            ),
          ),
        if (!pending &&
            (requestStatus == 'rejected' || requestStatus == 'corrections'))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IdentityNotice(
              'กรุณาแก้ไขแล้วส่งใหม่\n${reason ?? 'เจ้าหน้าที่ขอให้ตรวจสอบข้อมูลอีกครั้ง'}',
              error: true,
            ),
          ),
        _photoTile(
          'รูปคู่บัตรประชาชน',
          'เห็นใบหน้าและรายละเอียดบัตรชัดเจน เจ้าของบัตรถือบัตรของตนเองเท่านั้น',
          _photoBytes(state, true),
          true,
          editable,
        ),
        _photoTile(
          'รูปบัตรประชาชน',
          'เห็นด้านหน้าบัตรครบทุกมุม ข้อความชัดเจน ไม่มีแสงสะท้อน',
          _photoBytes(state, false),
          false,
          editable,
        ),
        _section(
          'ข้อมูลบัตรประชาชน',
          'กรอกข้อมูลภาษาไทยตามหน้าบัตร',
          Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('prefix-${_loaded.hashCode}'),
                initialValue:
                    [
                      'นาย',
                      'นางสาว',
                      'นาง',
                    ].contains(_fields['name_prefix']!.text)
                    ? _fields['name_prefix']!.text
                    : null,
                isExpanded: true,
                decoration: AppFormFieldStyles.decoration(
                  context,
                  variant: AppFormFieldVariant.outlined,
                ).copyWith(labelText: 'คำนำหน้าชื่อ'),
                items: const ['นาย', 'นางสาว', 'นาง']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: editable
                    ? (value) => setState(
                        () => _fields['name_prefix']!.text = value ?? '',
                      )
                    : null,
                validator: _required,
              ),
              const SizedBox(height: 20),
              _text('first_name', 'ชื่อ (ภาษาไทย)'),
              _text('last_name', 'นามสกุล (ภาษาไทย)'),
              _citizenField(),
              const SizedBox(height: 16),
              AppTextFormField(
                variant: AppFormFieldVariant.outlined,
                fieldKey: const ValueKey('birth_date'),
                label: 'วันเกิด (ปี ค.ศ.)',
                hintText: 'วัน/เดือน/ปี ค.ศ.',
                controller: _birthDisplay,
                readOnly: true,
                onTap: editable ? _birth : null,
                suffixIcon: const Icon(Icons.calendar_month_outlined),
                validator: (_) =>
                    identityValidBirthDate(_fields['birth_date']!.text)
                    ? null
                    : 'กรุณาเลือกวันเกิดให้ถูกต้อง',
              ),
            ],
          ),
        ),
        _section(
          'ที่อยู่ตามบัตรประชาชน',
          'เลือกพื้นที่เพื่อเติมรหัสไปรษณีย์อัตโนมัติ',
          _addressFields(),
        ),
        const IdentityNotice(
          'ข้อมูลใหม่จะมีผลหลังเจ้าหน้าที่อนุมัติเท่านั้น',
          icon: Icons.shield_outlined,
        ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<IdentityAccountCubit, IdentityAccountState>(
    listener: (context, state) {
      if (state.error != null) _message(state.error!);
      if (state.details != null && _loaded != state.details && !_dirty)
        setState(() => _hydrate(state.details!));
    },
    builder: (context, state) {
      if (_loaded == null && state.details != null) _hydrate(state.details!);
      final blocked =
          state.sent ||
          state.details?.pending == true ||
          state.details?.status.restricted == true;
      return PopScope(
        canPop: _allowExit,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: IdentityColors.canvas,
          appBar: AppBar(
            title: const Text(
              'ข้อมูลบัตรประชาชน',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: IdentityColors.ink,
            surfaceTintColor: Colors.transparent,
            leading: BackButton(onPressed: _back),
          ),
          body: state.loading
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: const IdentityAccountLoading(),
                    ),
                  ),
                )
              : state.details == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(state.error ?? 'โหลดข้อมูลไม่ได้'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _cubit.load,
                        child: const Text('ลองอีกครั้ง'),
                      ),
                    ],
                  ),
                )
              : AbsorbPointer(
                  absorbing: state.busy,
                  child: Form(
                    key: _form,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: _content(state),
                        ),
                      ),
                    ),
                  ),
                ),
          bottomNavigationBar: state.details == null && !state.loading
              ? null
              : Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: IdentityColors.line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppPrimaryButton(
                            text: blocked ? 'รอตรวจสอบ' : 'บันทึกข้อมูล',
                            isLoading: state.busy && !state.loading,
                            onPressed:
                                state.busy || blocked || !_dirty || _capturing
                                ? null
                                : () => _save(state),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'ตรวจสอบก่อนส่ง เพื่อให้ข้อมูลของคุณถูกต้องเสมอ',
                            style: TextStyle(
                              fontSize: 10,
                              color: IdentityColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      );
    },
  );
}
