import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/auth_session.dart';
import '../../../../../core/services/skeleton_layout_cache.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/promptpay_account.dart';
import '../../bloc/promptpay_account_cubit.dart';
import '../../widgets/promptpay_identifier_fields.dart';

const _outline = Color(0xFFE7DEEE);
const _lavender = Color(0xFFF4E9FC);
const _secondaryText = Color(0xFF62566C);
const _contentWidth = 520.0;

class PromptPayAccountScreen extends StatefulWidget {
  const PromptPayAccountScreen({super.key});

  @override
  State<PromptPayAccountScreen> createState() => _PromptPayAccountScreenState();
}

class _PromptPayAccountScreenState extends State<PromptPayAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  bool _nationalId = false;

  @override
  void initState() {
    super.initState();
    _setAccount(context.read<PromptPayAccountCubit>().state.account);
  }

  static String get _skeletonKey => 'promptpay.${AuthSession.userId}';

  /// จำว่าบัญชีใช้เบอร์หรือเลขบัตร มีเลขท้ายบัตร และมีค่าที่บันทึกไว้หรือไม่
  /// skeleton ครั้งหน้าจะเลือกปุ่มประเภทและแสดงกล่องแจ้งเตือนตรงกับหน้าจริง
  void _rememberLayout(PromptPayAccount account) {
    SkeletonLayoutCache.instance.write(_skeletonKey, [
      account.usesNationalId ? 'n' : 'p',
      account.nationalIdLastFour == null ? '-' : '4',
      (account.phone ?? '').isEmpty ? '-' : 'v',
    ]);
  }

  void _setAccount(PromptPayAccount? account) {
    _nationalId = account?.usesNationalId ?? false;
    _identifier.text = account?.phone ?? '';
  }

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  void _save() {
    final cubit = context.read<PromptPayAccountCubit>();
    if (cubit.state.busy) return;
    final invalidFields = _formKey.currentState?.validateGranularly();
    if (invalidFields == null) return;
    if (invalidFields.isNotEmpty) {
      final field = invalidFields.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!field.mounted) return;
        Scrollable.ensureVisible(
          field.context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 200),
        );
      });
      return;
    }
    FocusScope.of(context).unfocus();
    cubit.save(_identifier.text, nationalId: _nationalId);
  }

  void _changeType(bool nationalId) {
    FocusScope.of(context).unfocus();
    setState(() {
      _identifier.clear();
      _nationalId = nationalId;
    });
    context.read<PromptPayAccountCubit>().clearSaveError();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: BackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.settingAccount);
            }
          },
        ),
        title: const Text('แก้ไขพร้อมเพย์', style: AppTextStyles.headingMedium),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: BlocConsumer<PromptPayAccountCubit, PromptPayAccountState>(
          listenWhen: (previous, current) =>
              previous.account != current.account || current.saved,
          listener: (context, state) {
            _setAccount(state.account);
            final account = state.account;
            if (account != null) _rememberLayout(account);
            if (state.saved) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('บันทึกพร้อมเพย์แล้ว')),
                );
            }
          },
          builder: (context, state) {
            final account = state.account;
            final error = state.error;
            if (account == null && error == null) {
              return _PromptPayLoadingView(
                layout: SkeletonLayoutCache.instance.read(_skeletonKey),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _contentWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (account != null)
                              _buildForm(context, account, enabled: !state.busy)
                            else if (error != null)
                              _errorNotice(context, error),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _buildFooter(context, state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    PromptPayAccount account, {
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final lastFour = account.nationalIdLastFour;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (account.usesNationalId) ...[
                _PromptPayNotice(
                  icon: Icons.badge_outlined,
                  message: lastFour == null
                      ? 'กรอกเลขบัตรใหม่หรือเลือกเบอร์มือถือเพื่ออัปเดตพร้อมเพย์'
                      : 'เลขบัตรประชาชนที่บันทึกไว้ลงท้ายด้วย $lastFour',
                ),
                const SizedBox(height: 16),
              ],
              Text('ประเภทพร้อมเพย์', style: _sectionTitleStyle(theme)),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: _TypeLabel(
                      Icons.phone_android_rounded,
                      'เบอร์มือถือ',
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: _TypeLabel(Icons.badge_outlined, 'เลขบัตรประชาชน'),
                  ),
                ],
                selected: {_nationalId},
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                onSelectionChanged: enabled
                    ? (selection) => _changeType(selection.single)
                    : null,
                style: _typeSegmentStyle(),
              ),
              const SizedBox(height: 22),
              PromptPayIdentifierField(
                controller: _identifier,
                nationalId: _nationalId,
                enabled: enabled,
                decoration: _identifierDecoration(
                  theme,
                  nationalId: _nationalId,
                ),
                onChanged: (_) =>
                    context.read<PromptPayAccountCubit>().clearSaveError(),
                onSubmitted: _save,
              ),
              if (_nationalId) ...[
                const SizedBox(height: 12),
                const _PromptPayNotice(
                  icon: Icons.info_outline_rounded,
                  message:
                      'QR สำหรับรับค่าเช่าจะมีเลขบัตรประชาชนสำหรับการสแกนโอน',
                  background: Color(0xFFFFF6E6),
                  foreground: Color(0xFF684612),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, PromptPayAccountState state) {
    final error = state.error;
    final canEdit = state.account != null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _outline)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canEdit && error != null) ...[
                  _errorNotice(context, error),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: state.busy
                      ? null
                      : canEdit
                      ? _save
                      : context.read<PromptPayAccountCubit>().load,
                  icon: state.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          canEdit ? Icons.check_rounded : Icons.refresh_rounded,
                        ),
                  label: Text(
                    state.busy
                        ? 'กำลังบันทึก...'
                        : canEdit
                        ? 'บันทึกพร้อมเพย์'
                        : 'ลองอีกครั้ง',
                  ),
                  style: _saveButtonStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorNotice(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;
    return _PromptPayNotice(
      icon: Icons.error_outline_rounded,
      message: message,
      background: colors.errorContainer,
      foreground: colors.onErrorContainer,
      liveRegion: true,
    );
  }
}

class _TypeLabel extends StatelessWidget {
  const _TypeLabel(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class _PromptPayNotice extends StatelessWidget {
  const _PromptPayNotice({
    required this.icon,
    required this.message,
    this.background = _lavender,
    this.foreground = _secondaryText,
    this.liveRegion = false,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle? _sectionTitleStyle(ThemeData theme) =>
    theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);

ButtonStyle _typeSegmentStyle() {
  final selectionColors = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.selected)) return AppColors.primaryColor;
    return _secondaryText;
  });
  return ButtonStyle(
    foregroundColor: selectionColors,
    iconColor: selectionColors,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected) ? _lavender : Colors.white;
    }),
    side: const WidgetStatePropertyAll(BorderSide(color: _outline)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

InputDecoration _identifierDecoration(
  ThemeData theme, {
  required bool nationalId,
}) {
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _outline),
  );
  return InputDecoration(
    hintText: nationalId ? 'กรอกเลขบัตร 13 หลัก' : 'กรอกเบอร์มือถือ 10 หลัก',
    hintStyle: const TextStyle(color: _secondaryText, fontSize: 14),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    filled: true,
    fillColor: const Color(0xFFFCFAFE),
    border: fieldBorder,
    enabledBorder: fieldBorder,
    disabledBorder: fieldBorder,
    focusedBorder: fieldBorder.copyWith(
      borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
    ),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
      if (states.contains(WidgetState.error)) {
        return TextStyle(color: theme.colorScheme.error);
      }
      return const TextStyle(color: AppColors.primaryColor);
    }),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    errorMaxLines: 3,
  );
}

final _saveButtonStyle = FilledButton.styleFrom(
  backgroundColor: AppColors.primaryColor,
  foregroundColor: Colors.white,
  disabledBackgroundColor: _lavender,
  disabledForegroundColor: AppColors.primaryColor,
  minimumSize: const Size(0, 52),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
);

/// โครงหน้าพร้อมเพย์ขณะโหลด ใช้การ์ด ปุ่มเลือกประเภท ช่องกรอก และแถบปุ่มบันทึก
/// ชุดเดียวกับหน้าจริง ส่วนข้อความวางแบบมองไม่เห็นแล้วทับด้วยแถบ skeleton
/// ความสูงทุกส่วนจึงเท่าของจริงตามฟอนต์ที่ใช้อยู่
class _PromptPayLoadingView extends StatelessWidget {
  const _PromptPayLoadingView({this.layout});

  /// ['n' หรือ 'p', '4' ถ้ามีเลขท้ายบัตร, 'v' ถ้ามีค่าบันทึกไว้] จากการโหลดครั้งก่อน
  final List<String>? layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = layout ?? const ['p', '-', '-'];
    final nationalId = tokens.isNotEmpty && tokens[0] == 'n';
    final hasLastFour = tokens.length > 1 && tokens[1] == '4';
    final hasValue = tokens.length > 2 && tokens[2] == 'v';
    final decoration = _identifierDecoration(theme, nationalId: nationalId);
    return Semantics(
      label: 'กำลังโหลดข้อมูลพร้อมเพย์',
      child: ExcludeSemantics(
        key: const ValueKey('promptpay-loading-skeleton'),
        child: IgnorePointer(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentWidth,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _outline),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (nationalId) ...[
                                _NoticeSkeleton(
                                  message: hasLastFour
                                      ? 'เลขบัตรประชาชนที่บันทึกไว้ลงท้ายด้วย 0000'
                                      : 'กรอกเลขบัตรใหม่หรือเลือกเบอร์มือถือเพื่ออัปเดตพร้อมเพย์',
                                ),
                                const SizedBox(height: 16),
                              ],
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _GhostText(
                                  'ประเภทพร้อมเพย์',
                                  style: _sectionTitleStyle(theme),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: _TypeLabelSkeleton('เบอร์มือถือ'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: _TypeLabelSkeleton('เลขบัตรประชาชน'),
                                  ),
                                ],
                                selected: {nationalId},
                                expandedInsets: EdgeInsets.zero,
                                showSelectedIcon: false,
                                onSelectionChanged: null,
                                style: _typeSegmentStyle(),
                              ),
                              const SizedBox(height: 22),
                              // ใช้ labelText จริงแต่โปร่งใส ช่องจึงสูงเท่าช่องจริงทุกฟอนต์
                              // แล้ววางแถบ skeleton ทับตำแหน่งป้ายที่ลอยบนเส้นขอบ
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  InputDecorator(
                                    isEmpty: false,
                                    decoration: decoration.copyWith(
                                      // TextField จริงจำกัดข้อความแนะนำไว้บรรทัดเดียว
                                      hintMaxLines: 1,
                                      labelText: nationalId
                                          ? 'เลขบัตรประชาชนที่ผูกพร้อมเพย์'
                                          : 'เบอร์มือถือที่ผูกพร้อมเพย์',
                                      floatingLabelStyle: const TextStyle(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                    // ความสูงช่องจริงมาจากตัวอักษรที่พิมพ์ (bodyLarge)
                                    // แม้ตอนแสดงข้อความแนะนำ จึงใช้สไตล์เดียวกัน
                                    child: _GhostText(
                                      hasValue
                                          ? '0800000000'
                                          : decoration.hintText!,
                                      style: theme.textTheme.bodyLarge,
                                      maxLines: 1,
                                    ),
                                  ),
                                  PositionedDirectional(
                                    start: 16,
                                    top: -5,
                                    child: SkeletonShimmer(
                                      child: SkeletonBox(
                                        width: nationalId ? 170 : 140,
                                        height: 10,
                                        borderRadius: 4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (nationalId) ...[
                                const SizedBox(height: 12),
                                const _NoticeSkeleton(
                                  message:
                                      'QR สำหรับรับค่าเช่าจะมีเลขบัตรประชาชนสำหรับการสแกนโอน',
                                  background: Color(0xFFFFF6E6),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: _outline)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentWidth,
                      ),
                      child: const SkeletonShimmer(
                        child: SkeletonBox(height: 52, borderRadius: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ข้อความที่มองไม่เห็นแต่กินพื้นที่เท่าของจริง แล้ววางแถบ skeleton ทับ
class _GhostText extends StatelessWidget {
  const _GhostText(this.text, {this.style, this.textAlign, this.maxLines});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// ช่องกรอกจริงเป็นบรรทัดเดียว จึงต้องกันไม่ให้ข้อความแนะนำขึ้นบรรทัดใหม่
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Stack(
      children: [
        Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          softWrap: maxLines != 1,
          overflow: maxLines == null ? null : TextOverflow.clip,
          style: base.copyWith(color: Colors.transparent),
        ),
        const Positioned.fill(
          child: Center(
            child: FractionallySizedBox(
              heightFactor: 0.68,
              child: SkeletonShimmer(
                child: SkeletonBox(height: double.infinity, borderRadius: 5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ป้ายปุ่มเลือกประเภทแบบ _TypeLabel: ไอคอน 20 เว้น 4 แล้วตามด้วยชื่อ
class _TypeLabelSkeleton extends StatelessWidget {
  const _TypeLabelSkeleton(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonShimmer(
          child: SkeletonBox(width: 20, height: 20, borderRadius: 6),
        ),
        const SizedBox(height: 4),
        _GhostText(label, textAlign: TextAlign.center),
      ],
    );
  }
}

/// กล่องแจ้งเตือนแบบ _PromptPayNotice: พื้นสี มุม 12 ไอคอน 18 และข้อความ
class _NoticeSkeleton extends StatelessWidget {
  const _NoticeSkeleton({required this.message, this.background = _lavender});

  final String message;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonShimmer(
              child: SkeletonBox(width: 18, height: 18, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GhostText(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
