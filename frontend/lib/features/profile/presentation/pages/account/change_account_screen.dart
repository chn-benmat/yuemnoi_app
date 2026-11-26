import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/services/recommendation_location_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_popup.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_event.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../widgets/account/change_account_widgets.dart';

class ChangeAccountScreen extends StatefulWidget {
  const ChangeAccountScreen({super.key});

  @override
  State<ChangeAccountScreen> createState() => _ChangeAccountScreenState();
}

class _ChangeAccountScreenState extends State<ChangeAccountScreen> {
  bool _twoFactorEnabled = false;
  bool _profileSearchable = true;
  bool _deletingSavedLocation = false;

  final _locationService = RecommendationLocationService.instance;
  late Future<String?> _savedLocationOwner = _locationService
      .findSavedAccountLocationOwner();

  List<String> _blockedUsers = ['User_Demo99'];
  List<String> _hiddenUsers = ['Shop_Discount24'];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _twoFactorEnabled = prefs.getBool('sec_2fa') ?? false;
        _profileSearchable = prefs.getBool('sec_profile_search') ?? true;
        _blockedUsers =
            prefs.getStringList('sec_blocked_users') ?? ['User_Demo99'];
        _hiddenUsers =
            prefs.getStringList('sec_hidden_users') ?? ['Shop_Discount24'];
      });
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _saveStringList(String key, List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, list);
    } catch (_) {}
  }

  // ─── Modal Sheets ────────────────────────────────────────────────────────────

  void _showBlockedUsersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ผู้ใช้ที่ถูกบล็อก',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _promptAddUser(
                      title: 'บล็อกผู้ใช้',
                      hint: 'ใส่ชื่อผู้ใช้ที่ต้องการบล็อก',
                      onAdd: (username) {
                        if (username.isNotEmpty &&
                            !_blockedUsers.contains(username)) {
                          setState(() => _blockedUsers.add(username));
                          setSheetState(() {});
                          _saveStringList('sec_blocked_users', _blockedUsers);
                        }
                      },
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'เพิ่ม',
                      style: TextStyle(fontFamily: AppTextStyles.fontFamily),
                    ),
                  ),
                ],
              ),
              const Text(
                'ผู้ใช้ที่คุณบล็อกจะไม่สามารถส่งข้อความ หรือเช่าอุปกรณ์จากคุณได้',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: AppColors.hintTextColor,
                ),
              ),
              const SizedBox(height: 16),
              if (_blockedUsers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'ไม่มีรายชื่อผู้ใช้ที่ถูกบล็อก',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: AppColors.hintTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _blockedUsers.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, i) {
                      final username = _blockedUsers[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFEE2E2),
                          child: const Icon(
                            Icons.block_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          username,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            setState(() => _blockedUsers.removeAt(i));
                            setSheetState(() {});
                            _saveStringList('sec_blocked_users', _blockedUsers);
                          },
                          child: const Text(
                            'ปลดบล็อก',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHiddenUsersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ผู้ใช้ที่ซ่อนอยู่',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _promptAddUser(
                      title: 'ซ่อนผู้ใช้',
                      hint: 'ใส่ชื่อผู้ใช้ที่ต้องการซ่อน',
                      onAdd: (username) {
                        if (username.isNotEmpty &&
                            !_hiddenUsers.contains(username)) {
                          setState(() => _hiddenUsers.add(username));
                          setSheetState(() {});
                          _saveStringList('sec_hidden_users', _hiddenUsers);
                        }
                      },
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      'เพิ่ม',
                      style: TextStyle(fontFamily: AppTextStyles.fontFamily),
                    ),
                  ),
                ],
              ),
              const Text(
                'โพสต์และสินค้าของผู้ใช้เหล่านี้จะไม่แสดงบนหน้าแรกของคุณ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: AppColors.hintTextColor,
                ),
              ),
              const SizedBox(height: 16),
              if (_hiddenUsers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'ไม่มีรายชื่อผู้ใช้ที่ซ่อนอยู่',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: AppColors.hintTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _hiddenUsers.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, i) {
                      final username = _hiddenUsers[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFF3E8FF),
                          child: const Icon(
                            Icons.visibility_off_outlined,
                            color: AppColors.primaryColor,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          username,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            setState(() => _hiddenUsers.removeAt(i));
                            setSheetState(() {});
                            _saveStringList('sec_hidden_users', _hiddenUsers);
                          },
                          child: const Text(
                            'เลิกซ่อน',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActiveSessionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'อุปกรณ์ที่เข้าสู่ระบบอยู่',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  kIsWeb ? Icons.laptop_chromebook : Icons.phone_android,
                  color: const Color(0xFF2E7D32),
                ),
              ),
              title: Text(
                kIsWeb
                    ? 'เว็บเบราว์เซอร์ (ปัจจุบัน)'
                    : 'โทรศัพท์เครื่องนี้ (ปัจจุบัน)',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'ออนไลน์อยู่ • ปลอดภัย',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Color(0xFF2E7D32),
                  fontSize: 12,
                ),
              ),
              trailing: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 20,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
              },
              icon: const Icon(
                Icons.logout_rounded,
                color: Colors.red,
                size: 18,
              ),
              label: const Text(
                'ออกจากระบบจากอุปกรณ์อื่นทั้งหมด',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFECACA)),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final bloc = context.read<AuthBloc>();
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BlocConsumer<AuthBloc, AuthState>(
        bloc: bloc,
        buildWhen: (_, state) =>
            state is AccountDeletionLoading || state is AccountDeletionFailure,
        listenWhen: (_, state) => state is AccountDeletionScheduled,
        listener: (_, _) => Navigator.of(ctx).pop(true),
        builder: (context, state) {
          final isSubmitting = state is AccountDeletionLoading;
          return PopScope(
            canPop: !isSubmitting,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'ลบบัญชีผู้ใช้',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'โปรไฟล์และประกาศของคุณจะถูกซ่อนทันทีและคุณจะออกจากระบบ '
                    'บัญชีจะถูกลบถาวรหลัง 30 วัน คุณสามารถเข้าสู่ระบบเพื่อกู้คืนบัญชีได้ภายในกำหนดนี้',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (state is AccountDeletionFailure) ...[
                    const SizedBox(height: 12),
                    Text(
                      userFriendlyErrorMessage(state.message),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => bloc.add(const AuthAccountDeletionRequested()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isSubmitting ? 'กำลังส่งคำขอ...' : 'ยืนยันลบบัญชี',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (deleted != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ตั้งเวลาลบบัญชีแล้ว')));
    AppRoutes.goToLogin(context);
  }

  void _promptAddUser({
    required String title,
    required String hint,
    required ValueChanged<String> onAdd,
  }) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: AppTextStyles.fontFamily),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              onAdd(text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'บันทึก',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSavedLocation(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบตำแหน่งที่เคยบันทึกไว้?'),
        content: const Text('ระบบจะลบพิกัดที่เคยบันทึกไว้ในบัญชีคุณ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบตำแหน่ง'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _deletingSavedLocation = true);
    try {
      await _locationService.deleteSavedAccountLocation(userId);
      if (!mounted) return;
      setState(() => _savedLocationOwner = Future.value(null));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบตำแหน่งไม่สำเร็จ กรุณาลองใหม่')),
      );
    } finally {
      if (mounted) setState(() => _deletingSavedLocation = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ศูนย์ความเป็นส่วนตัว',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section: บัญชีและความปลอดภัย ──
            _buildSectionHeader('บัญชีและความปลอดภัย'),
            _buildCardGroup([
              AccountSecurityItem(
                icon: Icons.lock_outline_rounded,
                iconBgColor: const Color(0xFFF3E8FF),
                iconColor: AppColors.primaryColor,
                title: 'เปลี่ยนรหัสผ่าน',
                subtitle: 'อัปเดตรหัสผ่านของคุณเพื่อความปลอดภัย',
                onTap: () => AppRoutes.openProfileChangePassword(context),
              ),
              _buildDivider(),
              AccountSecuritySwitchItem(
                icon: Icons.verified_user_outlined,
                iconBgColor: const Color(0xFFE3F2FF),
                iconColor: const Color(0xFF1565C0),
                title: 'การยืนยันตัวตน 2 ขั้นตอน (2FA)',
                subtitle: 'เพิ่มการตรวจสอบสิทธิ์ความปลอดภัยเมื่อเข้าใช้งาน',
                value: _twoFactorEnabled,
                onChanged: (val) {
                  setState(() => _twoFactorEnabled = val);
                  _saveBool('sec_2fa', val);
                },
              ),
            ]),

            const SizedBox(height: 20),

            // ── Section: การจัดการการโต้ตอบและความเป็นส่วนตัว ──
            _buildSectionHeader('ความเป็นส่วนตัวและการบล็อก'),
            _buildCardGroup([
              AccountSecurityItem(
                icon: Icons.block_rounded,
                iconBgColor: const Color(0xFFFEE2E2),
                iconColor: Colors.red.shade700,
                title: 'จัดการผู้ใช้ที่บล็อก',
                subtitle: _blockedUsers.isEmpty
                    ? 'ไม่มีผู้ใช้ที่ถูกบล็อก'
                    : 'บล็อกอยู่ ${_blockedUsers.length} คน',
                onTap: _showBlockedUsersSheet,
              ),
              _buildDivider(),
              AccountSecurityItem(
                icon: Icons.visibility_off_outlined,
                iconBgColor: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                title: 'ซ่อนผู้ใช้ที่ไม่ต้องการเห็น',
                subtitle: _hiddenUsers.isEmpty
                    ? 'ไม่มีผู้ใช้ที่ซ่อนอยู่'
                    : 'ซ่อนอยู่ ${_hiddenUsers.length} คน',
                onTap: _showHiddenUsersSheet,
              ),
              _buildDivider(),
              AccountSecuritySwitchItem(
                icon: Icons.person_search_outlined,
                iconBgColor: const Color(0xFFF3E8FF),
                iconColor: AppColors.primaryColor,
                title: 'อนุญาตให้ค้นหาโปรไฟล์ของคุณ',
                subtitle: 'ผู้ใช้อื่นสามารถค้นหาคุณได้จากชื่อแสดงตัวตน',
                value: _profileSearchable,
                onChanged: (val) {
                  setState(() => _profileSearchable = val);
                  _saveBool('sec_profile_search', val);
                },
              ),
              FutureBuilder<String?>(
                future: _savedLocationOwner,
                builder: (context, snapshot) {
                  final userId = snapshot.data;
                  if (userId == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      _buildDivider(),
                      AccountSecurityItem(
                        icon: Icons.location_off_outlined,
                        iconBgColor: const Color(0xFFFEE2E2),
                        iconColor: Colors.red.shade700,
                        title: 'ลบตำแหน่งเดิมออกจากบัญชี',
                        subtitle: 'ลบพิกัดที่เคยบันทึกไว้ในบัญชี',
                        isDanger: true,
                        onTap: _deletingSavedLocation
                            ? null
                            : () => _deleteSavedLocation(userId),
                      ),
                    ],
                  );
                },
              ),
            ]),

            const SizedBox(height: 20),
            // ── Section: เซสชันและการจัดการบัญชี ──
            _buildSectionHeader('อุปกรณ์และการจัดการบัญชี'),
            _buildCardGroup([
              AccountSecurityItem(
                icon: Icons.devices_outlined,
                iconBgColor: const Color(0xFFE2E8F0),
                iconColor: const Color(0xFF475569),
                title: 'อุปกรณ์ที่เข้าสู่ระบบอยู่',
                subtitle: 'ตรวจสอบและออกจากระบบอุปกรณ์อื่น',
                onTap: _showActiveSessionsSheet,
              ),
              _buildDivider(),
              AccountSecurityItem(
                icon: Icons.delete_outline_rounded,
                iconBgColor: const Color(0xFFFEE2E2),
                iconColor: Colors.red.shade700,
                title: 'ลบบัญชีผู้ใช้',
                subtitle: 'ซ่อนโปรไฟล์และตั้งเวลาลบบัญชีถาวร',
                isDanger: true,
                onTap: _showDeleteAccountDialog,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: Colors.grey.shade100,
    );
  }
}
