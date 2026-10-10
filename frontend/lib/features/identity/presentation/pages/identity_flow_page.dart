import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../domain/identity_repository.dart';
import '../identity_cubit.dart';
import '../widgets/identity_camera_page.dart';
import '../widgets/identity_widgets.dart';

class IdentityPage extends StatefulWidget {
  const IdentityPage({super.key, this.capture = captureIdentityPhoto});
  final IdentityCapture capture;
  @override
  State<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends State<IdentityPage> {
  final _form = GlobalKey<FormState>(), _guardianForm = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _id = TextEditingController(),
      _birth = TextEditingController(),
      _expiry = TextEditingController();
  final _child = TextEditingController(),
      _relationship = TextEditingController();
  final _touched = <String>{};
  Uint8List? _card, _selfie, _authority;
  bool? _minor;
  bool _consent = false,
      _lifetime = false,
      _confirmed = false,
      _guardian = false,
      _guardianConsent = false,
      _guardianSent = false,
      _capturing = false,
      _allowExit = false;
  int _step = 0, _guardianStep = 0;
  String? _ocrMessage;
  late final Timer _clock;
  IdentityCubit get _cubit => context.read<IdentityCubit>();
  bool get _draft =>
      _card != null ||
      _selfie != null ||
      _authority != null ||
      _name.text.isNotEmpty ||
      _child.text.isNotEmpty;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _clear() {
    _card = null;
    _selfie = null;
    _authority = null;
    for (final c in [_name, _id, _birth, _expiry, _child, _relationship]) {
      c.clear();
    }
    _touched.clear();
    _confirmed = false;
    _guardianConsent = false;
    _ocrMessage = null;
  }

  @override
  void dispose() {
    _clock.cancel();
    _clear();
    for (final c in [_name, _id, _birth, _expiry, _child, _relationship]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_cubit.state.busy || _capturing) return;
    if (_guardian && !_guardianSent && _guardianStep > 0) {
      setState(() => _guardianStep--);
      return;
    }
    if (!_guardian && _cubit.state.session != null && _step > 0) {
      setState(() => _step--);
      return;
    }
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
    if (_guardian) {
      setState(() {
        _guardian = false;
        _guardianSent = false;
        _clear();
      });
      return;
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _capture(IdentityCaptureKind kind) async {
    if (_capturing || _cubit.state.busy) return;
    if (kind != IdentityCaptureKind.authority && !_liveSession(_cubit.state)) {
      _message('รอบถ่ายภาพหมดอายุ กรุณาเริ่มใหม่');
      await _cubit.load();
      return;
    }
    setState(() => _capturing = true);
    try {
      final bytes = await widget.capture(context, kind);
      if (!mounted || bytes == null) return;
      if (bytes.length > 5 * 1024 * 1024) {
        _message('ภาพต้องไม่เกิน 5 MB');
        return;
      }
      setState(() {
        if (kind == IdentityCaptureKind.card) {
          _card = bytes;
          _confirmed = false;
          _touched.clear();
          _name.clear();
          _id.clear();
          _birth.clear();
          _expiry.clear();
          _lifetime = false;
        } else if (kind == IdentityCaptureKind.selfie) {
          _selfie = bytes;
          _confirmed = false;
        } else {
          _authority = bytes;
        }
      });
      if (kind == IdentityCaptureKind.card) await _readCard();
    } catch (_) {
      if (mounted) _message('เปิดกล้องไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _readCard() async {
    final photo = _card;
    if (photo == null) return;
    final fields = await _cubit.readCard(photo);
    if (!mounted || !identical(photo, _card)) return;
    setState(() {
      for (final entry in {
        'legal_name': _name,
        'citizen_id': _id,
        'birth_date': _birth,
        'expires_on': _expiry,
      }.entries) {
        if (!_touched.contains(entry.key) &&
            fields?[entry.key]?.isNotEmpty == true) {
          entry.value.text = fields![entry.key]!;
        }
      }
      if (!_touched.contains('lifetime') && fields?['lifetime'] == 'true') {
        _lifetime = true;
      }
      _ocrMessage = fields == null || fields.isEmpty
          ? 'ยังอ่านข้อมูลไม่ครบ คุณถ่ายใหม่หรือกรอกข้อมูลเองในขั้นตอนถัดไปได้'
          : 'อ่านข้อมูลเบื้องต้นแล้ว กรุณาตรวจทุกช่องให้ตรงกับบัตรก่อนส่ง';
    });
  }

  bool _liveSession(IdentityState state) =>
      state.session != null &&
      state.captureUntil?.isAfter(DateTime.now()) == true;
  Future<void> _begin() async {
    await _cubit.begin(_minor!);
    if (mounted && _cubit.state.session != null) {
      setState(() {
        _clear();
        _step = 0;
      });
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณากรอกข้อมูลช่องนี้' : null;
  String? _citizen(String? value) {
    final s = value?.trim() ?? '';
    if (s.length != 13 || int.tryParse(s) == null) {
      return 'กรอกเลขบัตร 13 หลักให้ครบ';
    }
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(s[i]) * (13 - i);
    }
    return (11 - sum % 11) % 10 == int.parse(s[12])
        ? null
        : 'เลขบัตรไม่ถูกต้อง กรุณาตรวจอีกครั้ง';
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

  Future<void> _pickDate(TextEditingController controller, bool birth) async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(controller.text) ??
        (birth ? DateTime(now.year - 20, 1, 1) : DateTime(now.year + 5, 1, 1));
    var year = initial.year, month = initial.month, day = initial.day;
    year = year.clamp(1900, now.year + (birth ? 0 : 30));
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final days = DateTime(year, month + 1, 0).day;
          if (day > days) day = days;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    birth ? 'เลือกวันเกิด' : 'เลือกวันหมดอายุ',
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('$year-$month-$days'),
                          initialValue: day,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'วัน'),
                          items: [
                            for (var d = 1; d <= days; d++)
                              DropdownMenuItem(value: d, child: Text('$d')),
                          ],
                          onChanged: (v) => setSheet(() => day = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: month,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'เดือน'),
                          items: [
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem(value: m, child: Text('$m')),
                          ],
                          onChanged: (v) => setSheet(() => month = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: year,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'ปี พ.ศ.',
                          ),
                          items: [
                            for (
                              var y = now.year + (birth ? 0 : 30);
                              y >= 1900;
                              y--
                            )
                              DropdownMenuItem(
                                value: y,
                                child: Text('${y + 543}'),
                              ),
                          ],
                          onChanged: (v) => setSheet(() => year = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  AppPrimaryButton(
                    text: 'ใช้วันที่นี้',
                    onPressed: () =>
                        Navigator.pop(context, DateTime(year, month, day)),
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
        controller.text =
            '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
        _touched.add(birth ? 'birth_date' : 'expires_on');
        _confirmed = false;
      });
    }
  }

  Widget _dateField(
    TextEditingController controller,
    String label,
    bool birth,
  ) => FormField<String>(
    key: ValueKey('$label:${controller.text}'),
    validator: (_) {
      final date = DateTime.tryParse(controller.text);
      if (date == null) return 'กรุณาเลือกวันที่';
      final today = DateUtils.dateOnly(DateTime.now());
      if (birth && date.isAfter(today)) return 'วันเกิดต้องไม่อยู่ในอนาคต';
      if (!birth && date.isBefore(today)) {
        return 'บัตรหมดอายุ กรุณาใช้บัตรปัจจุบัน';
      }
      return null;
    },
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _pickDate(controller, birth),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(18),
            side: BorderSide(
              color: field.hasError
                  ? Theme.of(context).colorScheme.error
                  : IdentityColors.line,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dateText(controller.text),
                  style: const TextStyle(
                    color: IdentityColors.ink,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_month_outlined,
                size: 20,
                color: IdentityColors.primary,
              ),
            ],
          ),
        ),
        if (field.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
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
  );
  Widget _photo(Uint8List bytes, {double height = 190}) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Container(
      color: IdentityColors.tint,
      width: double.infinity,
      child: Image.memory(
        bytes,
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    ),
  );
  Widget _intro(IdentityStatus status) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: IdentityColors.tint,
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Text(
            'ก่อนเริ่มปล่อยเช่า',
            style: TextStyle(
              color: IdentityColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      const IdentityHeading(
        'ยืนยันตัวตน\nให้เช่ากันอย่างมั่นใจ',
        'เตรียมบัตรประชาชนและใบหน้าของคุณ\nเราจะช่วยอ่านข้อมูล แล้วให้คุณตรวจอีกครั้ง',
      ),
      const SizedBox(height: 24),
      const IdentityGuide(),
      const SizedBox(height: 20),
      const IdentityTip(
        Icons.badge_outlined,
        'บัตรประชาชนไทยตัวจริงที่ยังใช้ได้',
      ),
      const IdentityTip(
        Icons.wb_sunny_outlined,
        'อยู่ในที่สว่าง พร้อมเปิดกล้อง',
      ),
      const IdentityTip(
        Icons.fact_check_outlined,
        'ทุกคำขอให้เจ้าหน้าที่ตรวจสอบ',
      ),
      const SizedBox(height: 22),
      DropdownButtonFormField<bool>(
        initialValue: _minor,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'ช่วงอายุของคุณ',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
        items: const [
          DropdownMenuItem(
            value: false,
            child: Text(
              'อายุ 20 ปีขึ้นไป',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DropdownMenuItem(
            value: true,
            child: Text(
              'อายุต่ำกว่า 20 ปี',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        onChanged: (v) => setState(() => _minor = v),
      ),
      const SizedBox(height: 16),
      if (_minor == true && !status.guardianReady) ...[
        const IdentityNotice(
          'ให้ผู้ปกครองที่ยืนยันตัวตนแล้วเชื่อมบัญชีและส่งหลักฐานก่อน ระหว่างนี้ยังไม่เก็บภาพของคุณ',
        ),
        const SizedBox(height: 12),
        _guardianCode(),
        const SizedBox(height: 12),
      ],
      CheckboxListTile(
        value: _consent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: IdentityColors.primary,
        onChanged: (v) => setState(() => _consent = v ?? false),
        title: const Text(
          'ยินยอมให้ใช้ภาพบัตร ใบหน้า และข้อมูลเพื่อยืนยันตัวตน',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        subtitle: const Text(
          'สำหรับยืนยันตัวตนและให้เจ้าหน้าที่ตรวจสอบ',
          style: TextStyle(fontSize: 11, color: IdentityColors.muted),
        ),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'ข้อมูลของคุณถูกใช้ยังไง',
          style: TextStyle(fontSize: 13, color: IdentityColors.primary),
        ),
        children: const [
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'ใช้ภาพและข้อมูลเพื่อช่วยตรวจตัวตน เจ้าหน้าที่ที่ได้รับสิทธิ์เท่านั้นเข้าถึงหลักฐานได้ ภาพดิบลบตามกำหนดหลังพิจารณา ข้อมูลที่ยังไม่ส่งจะล้างเมื่อออกจากขั้นตอน',
              style: TextStyle(
                fontSize: 12,
                height: 1.8,
                color: IdentityColors.muted,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'ยังไม่ยืนยันก็ใช้งานแอปได้ ผู้ใหญ่เช่าได้ตามปกติ ผู้เยาว์ทำธุรกรรมผ่านผู้ปกครอง',
        style: TextStyle(
          fontSize: 12,
          height: 1.7,
          color: IdentityColors.muted,
        ),
      ),
    ],
  );

  Widget _guardianCode() {
    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    return IdentityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เชื่อมกับผู้ปกครอง',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'ส่งรหัสบัญชีให้ผู้ปกครองนำไปวางในเมนู “ดูแลบัญชีผู้เยาว์”',
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: IdentityColors.muted,
            ),
          ),
          TextButton.icon(
            onPressed: user == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: user));
                    if (mounted) _message('คัดลอกรหัสบัญชีแล้ว');
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('คัดลอกรหัสให้ผู้ปกครอง'),
          ),
        ],
      ),
    );
  }

  Widget _captureStep(bool face) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      IdentityHeading(
        face ? 'ให้เราเห็นใบหน้าคุณ' : 'เริ่มจากบัตรประชาชน',
        face
            ? 'มองตรงให้เห็นใบหน้าชัดเจน\nใช้ภาพถ่ายสดจากกล้องหน้าของคุณ'
            : 'ถ่ายด้านหน้าบัตรให้ครบทุกมุม\nระบบจะอ่านข้อมูลเพื่อช่วยกรอกให้',
      ),
      const SizedBox(height: 24),
      if ((face ? _selfie : _card) != null) ...[
        _photo((face ? _selfie : _card)!),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _cubit.state.busy || _capturing
              ? null
              : () => _capture(
                  face ? IdentityCaptureKind.selfie : IdentityCaptureKind.card,
                ),
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('ถ่ายรูปใหม่'),
        ),
      ] else
        IdentityGuide(face: face),
      const SizedBox(height: 20),
      if (face) ...const [
        IdentityTip(
          Icons.face_outlined,
          'เห็นใบหน้าครบ ไม่ใส่หน้ากากหรือแว่นกันแดด',
        ),
        IdentityTip(Icons.light_mode_outlined, 'แสงส่องด้านหน้า เลี่ยงย้อนแสง'),
        IdentityTip(Icons.person_outline, 'ถ่ายเฉพาะตัวคุณคนเดียว'),
      ] else ...const [
        IdentityTip(
          Icons.crop_free_rounded,
          'เห็นบัตรครบ ไม่ตัดขอบหรือปิดตัวอักษร',
        ),
        IdentityTip(Icons.wb_sunny_outlined, 'วางบนพื้นเรียบ เลี่ยงแสงสะท้อน'),
        IdentityTip(
          Icons.auto_fix_high_outlined,
          'ตรวจแก้ข้อมูลที่อ่านได้ก่อนส่งเสมอ',
        ),
      ],
      if (!face && _ocrMessage != null) ...[
        const SizedBox(height: 16),
        IdentityNotice(_ocrMessage!),
        TextButton(
          onPressed: _cubit.state.busy || _capturing ? null : _readCard,
          child: const Text('ลองอ่านข้อมูลอีกครั้ง'),
        ),
      ],
    ],
  );
  Widget _details() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IdentityHeading(
          'ตรวจข้อมูลให้ตรงบัตร',
          'เราเติมข้อมูลที่อ่านได้ให้แล้ว\nคุณแก้ไขหรือกรอกช่องที่ยังว่างได้',
        ),
        const SizedBox(height: 20),
        const IdentityNotice(
          'การอ่านบัตรอาจคลาดเคลื่อน กรุณาตรวจชื่อ เลขบัตร และวันที่ทุกครั้ง',
        ),
        const SizedBox(height: 20),
        AppTextFormField(
          label: 'ชื่อและนามสกุลตามบัตร',
          controller: _name,
          validator: _required,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            _touched.add('legal_name');
            _confirmed = false;
          },
        ),
        const SizedBox(height: 20),
        AppTextFormField(
          label: 'เลขบัตรประชาชน 13 หลัก',
          controller: _id,
          validator: _citizen,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
          onChanged: (_) {
            _touched.add('citizen_id');
            _confirmed = false;
          },
        ),
        const SizedBox(height: 20),
        _dateField(_birth, 'วันเกิด', true),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _lifetime,
          contentPadding: EdgeInsets.zero,
          activeColor: IdentityColors.primary,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            _lifetime = v ?? false;
            _touched.add('lifetime');
            _confirmed = false;
          }),
          title: const Text('บัตรตลอดชีพ', style: TextStyle(fontSize: 14)),
        ),
        if (!_lifetime) ...[
          _dateField(_expiry, 'วันหมดอายุ', false),
          const SizedBox(height: 12),
        ],
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
  Widget _review() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const IdentityHeading(
        'อีกนิดเดียว พร้อมส่งแล้ว',
        'ตรวจรูปและข้อมูลของคุณ\nเมื่อส่งแล้ว เจ้าหน้าที่จะตรวจคำขอ',
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _photo(_card!, height: 110),
                const SizedBox(height: 8),
                const Text(
                  'บัตรประชาชน',
                  style: TextStyle(fontSize: 12, color: IdentityColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                _photo(_selfie!, height: 110),
                const SizedBox(height: 8),
                const Text(
                  'ใบหน้าของคุณ',
                  style: TextStyle(fontSize: 12, color: IdentityColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      IdentityPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryRow('ชื่อและนามสกุล', _name.text.trim()),
            _summaryRow('เลขบัตรประชาชน', '•••••••••${_id.text.substring(9)}'),
            _summaryRow('วันเกิด', _dateText(_birth.text)),
            _summaryRow(
              'วันหมดอายุ',
              _lifetime ? 'ตลอดชีพ' : _dateText(_expiry.text),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('แก้ไขข้อมูล'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _confirmed,
        activeColor: IdentityColors.primary,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() => _confirmed = v ?? false),
        title: const Text(
          'ตรวจแล้ว ข้อมูลและรูปทั้งหมดเป็นของฉันและถูกต้อง',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
      ),
      const IdentityNotice(
        'ผลอ่านบัตรและคะแนนเปรียบเทียบใบหน้าเป็นข้อมูลช่วยตรวจ ทุกคำขอให้เจ้าหน้าที่เป็นผู้พิจารณา',
        icon: Icons.fact_check_outlined,
      ),
    ],
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
            : 'ตัวตนของคุณผ่านแล้ว การทำธุรกรรมยังเป็นไปตามข้อกำหนดบัญชีและผู้ปกครอง',
      'pending' => 'เจ้าหน้าที่กำลังรอตรวจข้อมูล\nกลับมาเช็กสถานะที่หน้านี้ได้',
      'corrections' =>
        'อ่านคำแนะนำจากเจ้าหน้าที่ แล้วเริ่มถ่ายและส่งข้อมูลที่ถูกต้องอีกครั้ง',
      'rejected' => 'ตรวจเหตุผลจากเจ้าหน้าที่ก่อนเริ่มคำขอใหม่',
      'suspended' => 'กรุณาติดต่อผู้ดูแลเพื่อสอบถามรายละเอียด',
      'unavailable' =>
        'ระบบกำลังทดลองเฉพาะบัญชีที่ได้รับเชิญ กรุณากลับมาใหม่ภายหลัง',
      _ =>
        'บัตรหรือรอบถ่ายภาพเดิมหมดอายุ\nเตรียมบัตรปัจจุบันและเริ่มรอบใหม่ได้',
    };
    final icon = approved
        ? Icons.verified_rounded
        : pending
        ? Icons.hourglass_top_rounded
        : Icons.assignment_outlined;
    final color = approved ? IdentityColors.success : IdentityColors.primary;
    final reason = status.request['reason'] ?? status.request['review_reason'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, color: color, size: 38),
          ),
        ),
        const SizedBox(height: 24),
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
              children: [
                _summaryRow('สถานะ', 'ผ่านการอนุมัติ'),
                _summaryRow(
                  'ใช้ได้ถึง',
                  status.profile['lifetime'] == true
                      ? 'บัตรตลอดชีพ'
                      : _dateText(
                          status.profile['expires_on']?.toString() ?? '',
                        ),
                ),
              ],
            ),
          ),
          if (status.canList) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _guardian = true;
                _guardianStep = 0;
                _guardianSent = false;
              }),
              icon: const Icon(Icons.family_restroom_outlined),
              label: const Text('ดูแลบัญชีผู้เยาว์'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _guardianBody() {
    if (_guardianSent) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdentityHeading(
            'ส่งคำขอผู้ปกครองแล้ว',
            'เจ้าหน้าที่จะตรวจความสัมพันธ์และหลักฐาน\nผู้เยาว์เริ่มยืนยันได้เมื่อคำขอนี้อนุมัติ',
          ),
          SizedBox(height: 24),
          IdentityNotice(
            'ผู้เยาว์กลับมาโหลดสถานะในหน้ายืนยันตัวตน เพื่อเช็กความพร้อมได้',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdentityProgress(
          step: _guardianStep,
          labels: const ['เชื่อมบัญชี', 'หลักฐาน', 'ส่งคำขอ'],
        ),
        const SizedBox(height: 28),
        if (_guardianStep == 0)
          Form(
            key: _guardianForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const IdentityHeading(
                  'ดูแลบัญชีผู้เยาว์',
                  'ให้ผู้เยาว์คัดลอกรหัสจากหน้าของเขา\nแล้ววางรหัสเพื่อเชื่อมกับบัญชีของคุณ',
                ),
                const SizedBox(height: 24),
                AppTextFormField(
                  label: 'รหัสบัญชีผู้เยาว์',
                  controller: _child,
                  validator: (v) =>
                      RegExp(
                        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
                      ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'กรุณาวางรหัสที่คัดลอกจากบัญชีผู้เยาว์',
                  suffixIcon: IconButton(
                    tooltip: 'วางรหัสบัญชี',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (mounted) _child.text = data?.text?.trim() ?? '';
                    },
                  ),
                ),
                const SizedBox(height: 20),
                AppTextFormField(
                  label: 'ความสัมพันธ์กับผู้เยาว์',
                  hintText: 'เช่น บิดา มารดา หรือผู้ปกครอง',
                  controller: _relationship,
                  validator: _required,
                ),
                const SizedBox(height: 20),
                const IdentityNotice(
                  'การเชื่อมบัญชีจะมีผลเมื่อเจ้าหน้าที่ตรวจอำนาจผู้ปกครองแล้ว',
                ),
              ],
            ),
          ),
        if (_guardianStep == 1) ...[
          const IdentityHeading(
            'หลักฐานผู้ปกครอง',
            'ถ่ายเอกสารที่แสดงอำนาจผู้ปกครอง\nให้เห็นข้อมูลและความสัมพันธ์ชัดเจน',
          ),
          const SizedBox(height: 24),
          if (_authority != null)
            _photo(_authority!)
          else
            const IdentityGuide(),
          const SizedBox(height: 16),
          if (_authority != null)
            TextButton.icon(
              onPressed: () => _capture(IdentityCaptureKind.authority),
              icon: const Icon(Icons.replay),
              label: const Text('ถ่ายหลักฐานใหม่'),
            ),
          const IdentityNotice(
            'เจ้าหน้าที่ตรวจหลักฐานและอำนาจผู้ปกครองด้วยตนเอง',
          ),
        ],
        if (_guardianStep == 2) ...[
          const IdentityHeading(
            'ตรวจคำขอผู้ปกครอง',
            'ตรวจบัญชี ความสัมพันธ์ และรูปเอกสาร\nให้ถูกต้องก่อนส่ง',
          ),
          const SizedBox(height: 24),
          IdentityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(
                  'รหัสบัญชีผู้เยาว์',
                  '••••${_child.text.trim().substring(_child.text.trim().length - 8)}',
                ),
                _summaryRow('ความสัมพันธ์', _relationship.text.trim()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _photo(_authority!),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _guardianConsent,
            contentPadding: EdgeInsets.zero,
            activeColor: IdentityColors.primary,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _guardianConsent = v ?? false),
            title: const Text(
              'ยินยอมให้ตรวจอำนาจผู้ปกครองและดำเนินการยืนยันตัวตนของผู้เยาว์',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            subtitle: const Text(
              'นโยบาย guardian-v1',
              style: TextStyle(fontSize: 11),
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
    if (state.session != null) {
      return _liveSession(state) ? 'capture' : 'expired';
    }
    final request = s.request;
    final status = request['status'];
    if (status == 'pending') {
      final deadline = DateTime.tryParse(request['deadline']?.toString() ?? '');
      return deadline?.isBefore(DateTime.now()) == true ? 'expired' : 'pending';
    }
    if (['rejected', 'corrections', 'expired'].contains(status)) {
      return status as String;
    }
    if (s.profile['status'] == 'approved') return 'expired';
    if (!s.available) return 'unavailable';
    return 'intro';
  }

  ({String text, VoidCallback? action, String? helper}) _action(
    IdentityState state,
    String kind,
  ) {
    if (_guardian) {
      if (_guardianSent) {
        return (
          text: 'กลับหน้าสถานะ',
          action: () {
            setState(() {
              _clear();
              _guardian = false;
              _guardianSent = false;
            });
          },
          helper: null,
        );
      }
      if (_guardianStep == 0) {
        return (
          text: 'ถัดไป: ถ่ายหลักฐาน',
          action: () {
            if (_guardianForm.currentState?.validate() == true) {
              setState(() => _guardianStep = 1);
            }
          },
          helper: null,
        );
      }
      if (_guardianStep == 1) {
        return (
          text: _authority == null ? 'ถ่ายหลักฐานผู้ปกครอง' : 'ถัดไป: ตรวจคำขอ',
          action: () {
            if (_authority == null) {
              _capture(IdentityCaptureKind.authority);
            } else {
              setState(() => _guardianStep = 2);
            }
          },
          helper: null,
        );
      }
      return (
        text: 'ส่งคำขอผู้ปกครอง',
        action: _guardianConsent
            ? () async {
                if (await _cubit.guardian(
                      _child.text.trim(),
                      _relationship.text.trim(),
                      _authority!,
                    ) &&
                    mounted) {
                  setState(() {
                    _clear();
                    _guardianSent = true;
                  });
                }
              }
            : null,
        helper: _guardianConsent ? null : 'ยืนยันความยินยอมด้านบนก่อนส่ง',
      );
    }
    if (kind == 'intro') {
      return (
        text: 'ยินยอมและเริ่มยืนยัน',
        action:
            _minor != null &&
                _consent &&
                (_minor == false || state.status!.guardianReady)
            ? _begin
            : null,
        helper: _minor == null
            ? 'เลือกช่วงอายุเพื่อเริ่มต้น'
            : !_consent
            ? 'อ่านและยืนยันความยินยอมก่อนเริ่ม'
            : _minor == true && !state.status!.guardianReady
            ? 'รอผู้ปกครองเชื่อมบัญชีและผ่านการตรวจ'
            : null,
      );
    }
    if (kind == 'capture') {
      if (_step == 0) {
        return (
          text: _card == null ? 'ถ่ายบัตรประชาชน' : 'ถัดไป: ถ่ายใบหน้า',
          action: () {
            if (_card == null) {
              _capture(IdentityCaptureKind.card);
            } else {
              setState(() => _step = 1);
            }
          },
          helper: state.busy
              ? 'กำลังอ่านบัตร คุณตรวจแก้ข้อมูลได้ในขั้นตอนถัดไป'
              : null,
        );
      }
      if (_step == 1) {
        return (
          text: _selfie == null ? 'ถ่ายใบหน้า' : 'ถัดไป: ตรวจข้อมูล',
          action: () {
            if (_selfie == null) {
              _capture(IdentityCaptureKind.selfie);
            } else {
              setState(() => _step = 2);
            }
          },
          helper: null,
        );
      }
      if (_step == 2) {
        return (
          text: 'ตรวจสรุปก่อนส่ง',
          action: () {
            FocusScope.of(context).unfocus();
            if (_form.currentState?.validate() == true) {
              setState(() => _step = 3);
            }
          },
          helper: null,
        );
      }
      return (
        text: 'ส่งคำขอยืนยันตัวตน',
        action: _confirmed
            ? () async {
                final sent = await _cubit.submit(
                  {
                    'legal_name': _name.text.trim(),
                    'citizen_id': _id.text.trim(),
                    'birth_date': _birth.text,
                    'expires_on': _expiry.text,
                    'lifetime': '$_lifetime',
                  },
                  _card!,
                  _selfie!,
                );
                if (sent && mounted) setState(_clear);
              }
            : null,
        helper: _confirmed ? null : 'ตรวจข้อมูลและยืนยันด้านบนก่อนส่ง',
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
            _step = 0;
            _consent = false;
          });
          _cubit.resetCapture();
        },
        helper: null,
      );
    }
    return (text: 'โหลดสถานะใหม่', action: _cubit.load, helper: null);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<IdentityCubit, IdentityState>(
    builder: (context, state) {
      final kind = _kind(state), action = _action(state, kind);
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
            actions: [
              IconButton(
                tooltip: 'โหลดสถานะใหม่',
                onPressed: state.busy || _capturing ? null : _cubit.load,
                icon: const Icon(Icons.refresh_rounded, size: 22),
              ),
            ],
          ),
          body: ResponsivePageBody(
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
                if (_guardian)
                  _guardianBody()
                else if (kind == 'loading')
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: Text(
                        'กำลังโหลดสถานะของคุณ…',
                        style: TextStyle(color: IdentityColors.muted),
                      ),
                    ),
                  )
                else if (kind == 'intro')
                  _intro(state.status!)
                else if (kind == 'capture') ...[
                  IdentityProgress(step: _step),
                  const SizedBox(height: 28),
                  if (_step < 2)
                    _captureStep(_step == 1)
                  else if (_step == 2)
                    _details()
                  else
                    _review(),
                  const SizedBox(height: 20),
                  Text(
                    'รอบถ่ายภาพใช้ได้ถึง ${state.captureUntil!.toLocal().hour.toString().padLeft(2, '0')}:${state.captureUntil!.toLocal().minute.toString().padLeft(2, '0')} น.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: IdentityColors.muted,
                    ),
                  ),
                ] else
                  _status(state.status!, kind),
                const SizedBox(height: 16),
              ],
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
                        fontSize: 11,
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
