import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/widgets/app_primary_button.dart';

class IdentityColors {
  IdentityColors._();
  static const primary = AppColors.primaryColor;
  static const ink = Color(0xFF241B32);
  static const muted = Color(0xFF746C80);
  static const canvas = Color(0xFFFAF8FD);
  static const line = Color(0xFFEAE4F1);
  static const tint = Color(0xFFF1E7FC);
  static const success = Color(0xFF18734E);
  static const warning = Color(0xFF926012);
  static const danger = Color(0xFFB23B3B);
}

class IdentityHeading extends StatelessWidget {
  const IdentityHeading(this.title, this.subtitle, {super.key, this.eyebrow});
  final String title, subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!,
          style: const TextStyle(
            color: IdentityColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        title,
        style: const TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: IdentityColors.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          height: 1.7,
          color: IdentityColors.muted,
        ),
      ),
    ],
  );
}

class IdentityPanel extends StatelessWidget {
  const IdentityPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 20,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: IdentityColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class IdentityNotice extends StatelessWidget {
  const IdentityNotice(
    this.text, {
    super.key,
    this.error = false,
    this.icon = Icons.info_outline_rounded,
  });
  final String text;
  final bool error;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : IdentityColors.primary;
    return Semantics(
      liveRegion: error,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline_rounded : icon,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: error ? color : IdentityColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IdentityProgress extends StatelessWidget {
  const IdentityProgress({
    super.key,
    required this.step,
    this.labels = const ['เตรียมพร้อม', 'ถ่ายภาพ', 'ข้อมูลและส่ง'],
  });
  final int step;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ขั้นตอน ${step + 1} จาก ${labels.length} ${labels[step]}',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ขั้นตอน ${step + 1} / ${labels.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: IdentityColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  labels[step],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: IdentityColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              labels.length,
              (index) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index == labels.length - 1 ? 0 : 6,
                  ),
                  height: 5,
                  decoration: BoxDecoration(
                    color: index <= step
                        ? IdentityColors.primary
                        : IdentityColors.line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class IdentityGuide extends StatelessWidget {
  const IdentityGuide({super.key, this.face = false});
  final bool face;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.7,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: IdentityColors.tint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: face
            ? Container(
                width: 100,
                height: 125,
                decoration: BoxDecoration(
                  border: Border.all(color: IdentityColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(65),
                ),
                child: const Icon(
                  Icons.face_outlined,
                  size: 66,
                  color: IdentityColors.primary,
                ),
              )
            : Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: IdentityColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 46,
                      color: IdentityColors.primary,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final width in [1.0, 0.8, 0.55])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: FractionallySizedBox(
                                widthFactor: width,
                                child: Container(
                                  height: 5,
                                  color: IdentityColors.line,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class IdentityTip extends StatelessWidget {
  const IdentityTip(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: IdentityColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: IdentityColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class IdentitySectionTitle extends StatelessWidget {
  const IdentitySectionTitle(this.title, {super.key, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: IdentityColors.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: IdentityColors.ink,
          ),
        ),
      ),
    ],
  );
}

class IdentityConsentDialog extends StatefulWidget {
  const IdentityConsentDialog({super.key, this.requiresConsent = true});
  final bool requiresConsent;

  @override
  State<IdentityConsentDialog> createState() => _IdentityConsentDialogState();
}

class _IdentityConsentDialogState extends State<IdentityConsentDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.requiresConsent,
    child: Dialog(
      key: const ValueKey('identity_consent_dialog'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              child: Semantics(
                header: true,
                child: const Text(
                  'เงื่อนไขการเก็บข้อมูลบัตรประชาชน',
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: IdentityColors.ink,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: IdentityColors.line),
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IdentityConsentSection('1. ข้อมูลที่เก็บ', [
                      'คำนำหน้าชื่อ ชื่อและนามสกุล เลขประจำตัวประชาชน วันเกิด และที่อยู่ตามบัตร',
                      'ภาพด้านหน้าบัตรประชาชนและภาพถ่ายใบหน้าที่คุณส่งเป็นหลักฐาน เช่น ภาพถ่ายคู่บัตรประชาชน',
                    ]),
                    _IdentityConsentSection('2. วัตถุประสงค์และวิธีใช้ข้อมูล', [
                      'Yuemnoi ใช้ข้อมูลและภาพที่คุณส่งเพื่อให้เจ้าหน้าที่ตรวจสอบว่าคุณเป็นเจ้าของบัตร และบันทึกผลการยืนยันตัวตนกับบัญชีของคุณ',
                      'แอปจะส่งข้อมูลและรูปใหม่ไปให้เจ้าหน้าที่ตรวจสอบเมื่อคุณยืนยันส่งคำขอ',
                    ]),
                    _IdentityConsentSection('3. ผู้ที่เข้าถึงข้อมูล', [
                      'คุณดูรูปหน้าบัตรที่เก็บไว้ได้จากหน้าข้อมูลบัตรประชาชน เจ้าหน้าที่ Yuemnoi ที่ได้รับสิทธิ์เข้าถึงข้อมูลและรูปเพื่อพิจารณาคำขอและตรวจสอบข้อมูลยืนยันตัวตน',
                      'ผู้ให้บริการระบบจัดเก็บข้อมูลประมวลผลข้อมูลและรูปหลักฐานเพื่อให้ Yuemnoi จัดเก็บและเรียกดูได้',
                    ]),
                    _IdentityConsentSection('4. การเก็บรักษาและลบข้อมูล', [
                      'ระบบเก็บรูปหน้าบัตรล่าสุดที่อนุมัติไว้กับบัญชี จนกว่าจะมีรูปที่อนุมัติมาแทนหรือมีการลบบัญชี',
                      'ระบบเก็บข้อมูลบัตรที่อนุมัติล่าสุดแบบเข้ารหัส จนกว่าจะมีข้อมูลที่ได้รับอนุมัติมาแทนที่หรือมีการลบบัญชี',
                    ]),
                    _IdentityConsentSection('5. การเลือกให้ความยินยอม', [
                      'หากยังไม่ยินยอม คุณจะบันทึกหรือส่งข้อมูลบัตรเพื่อยืนยันตัวตนไม่ได้ และสามารถกลับมาให้ความยินยอมได้ภายหลัง',
                      'หากต้องการถอนความยินยอมหลังส่งข้อมูล ให้แจ้งทีมงานผ่านช่องทางในข้อ 6 การถอนความยินยอมไม่มีผลย้อนหลังต่อการใช้ข้อมูลโดยชอบก่อนถอน',
                    ]),
                    _IdentityConsentSection('6. สิทธิและช่องทางติดต่อ', [
                      'คุณขอเข้าถึง รับสำเนา แก้ไข ลบ จำกัดการใช้ คัดค้านการใช้ หรือขอโอนข้อมูลของคุณได้ตามที่กฎหมายกำหนด',
                      'หากต้องการใช้สิทธิหรือสอบถามเรื่องข้อมูลส่วนบุคคล ให้ไปที่หน้า «โปรไฟล์» แล้วเลือก «ติดต่อเจ้าหน้าที่» เพื่อแจ้งทีมงาน Yuemnoi',
                      'คุณสามารถร้องเรียนเรื่องข้อมูลส่วนบุคคลผ่านช่องทางของสำนักงานคณะกรรมการคุ้มครองข้อมูลส่วนบุคคลได้',
                    ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: IdentityColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.requiresConsent)
                    CheckboxListTile(
                      value: _checked,
                      onChanged: (value) =>
                          setState(() => _checked = value == true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'ฉันยินยอมให้ Yuemnoi เก็บและใช้ข้อมูลบัตรประชาชนและรูปหลักฐานเพื่อยืนยันตัวตน',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  if (widget.requiresConsent) const SizedBox(height: 12),
                  AppPrimaryButton(
                    text: widget.requiresConsent
                        ? 'ยินยอมและดำเนินการต่อ'
                        : 'เข้าใจแล้ว',
                    onPressed: !widget.requiresConsent || _checked
                        ? () => Navigator.pop(context, true)
                        : null,
                  ),
                  if (widget.requiresConsent) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('ไว้ก่อน'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IdentityConsentSection extends StatelessWidget {
  const _IdentityConsentSection(this.title, this.details);

  final String title;
  final List<String> details;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: IdentityColors.ink,
            ),
          ),
        ),
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 8),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: IdentityColors.ink,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•')),
                  const SizedBox(width: 8),
                  Expanded(child: Text(detail)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class IdentityPhotoTile extends StatelessWidget {
  const IdentityPhotoTile({
    super.key,
    required this.title,
    required this.icon,
    required this.bytes,
    required this.onRetake,
  });
  final String title;
  final IconData icon;
  final Uint8List? bytes;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) => IdentityPanel(
    padding: 12,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 100,
            color: IdentityColors.canvas,
            child: bytes == null
                ? Icon(icon, size: 36, color: IdentityColors.muted)
                : Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: IdentityColors.ink,
          ),
        ),
        TextButton(
          onPressed: onRetake,
          style: TextButton.styleFrom(
            foregroundColor: IdentityColors.primary,
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Text(
            bytes == null ? 'ถ่ายภาพ' : 'ถ่ายใหม่',
            maxLines: 1,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
