import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/services/app_permission_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_popup.dart';
import '../../bloc/profile_cubit.dart';
import '../../bloc/profile_state.dart';
import '../../widgets/account/edit_profile_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.cubit});

  final ProfileCubit? cubit;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static final _invalidUsernameCharacters = RegExp(r'[^A-Za-z0-9._]');
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final ProfileCubit _cubit;

  String? _avatarUrl;
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  Timer? _usernameUnlockTimer;

  DateTime? get _usernameAvailableAt =>
      _cubit.currentProfile?.usernameChangeAvailableAt;

  bool get _usernameLocked =>
      _usernameAvailableAt?.isAfter(DateTime.now()) ?? false;

  bool get _canEditUsername =>
      _cubit.state is! ProfileLoading &&
      _cubit.currentProfile?.username.isNotEmpty == true &&
      !_usernameLocked;

  @override
  void initState() {
    super.initState();
    _cubit = widget.cubit ?? ProfileCubit();

    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;
    final meta = user?.userMetadata ?? {};
    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    if (widget.cubit == null && user != null) {
      unawaited(
        _cubit.loadProfile(userId: user.id, accessToken: session?.accessToken),
      );
    }
    _displayNameCtrl = TextEditingController(
      text:
          (meta['display_name'] ??
                  meta['full_name'] ??
                  user?.email?.split('@').first ??
                  '')
              .toString(),
    );
    _usernameCtrl = TextEditingController(
      text: _cubit.currentProfile?.username ?? meta['username']?.toString(),
    );
    _bioCtrl = TextEditingController(text: (meta['bio'] ?? '').toString());
    _avatarUrl =
        (meta['user_image_url'] ?? meta['avatar_url'] ?? meta['picture'] ?? '')
            .toString();
    if (_avatarUrl!.isEmpty) _avatarUrl = null;

    _scheduleUsernameUnlock();
  }

  void _scheduleUsernameUnlock() {
    _usernameUnlockTimer?.cancel();
    final remaining = _usernameAvailableAt?.difference(DateTime.now());
    if (remaining != null && remaining > Duration.zero) {
      _usernameUnlockTimer = Timer(remaining, () => setState(() {}));
    }
  }

  @override
  void dispose() {
    _usernameUnlockTimer?.cancel();
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    if (widget.cubit == null) _cubit.close();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final hasPermission = await AppPermissionService.requestGalleryPermission(
      context,
    );
    if (!hasPermission || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageName = picked.name;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final accessToken = session?.accessToken;
    if (accessToken == null) {
      showAppPopup(context, content: Text('กรุณาเข้าสู่ระบบก่อน'));
      return;
    }

    await _cubit.updateProfileData(
      accessToken: accessToken,
      displayName: _displayNameCtrl.text.trim(),
      username:
          _canEditUsername &&
              _usernameCtrl.text != _cubit.currentProfile?.username
          ? _usernameCtrl.text
          : null,
      bio: _bioCtrl.text.trim(),
      imageBytes: _pickedImageBytes,
      imageName: _pickedImageName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state is ProfileLoaded) {
            if (_displayNameCtrl.text.isEmpty &&
                state.profile.displayName.isNotEmpty) {
              _displayNameCtrl.text = state.profile.displayName;
            }
            if (state.profile.username.isNotEmpty &&
                _usernameCtrl.text != state.profile.username) {
              _usernameCtrl.text = state.profile.username;
            }
            _scheduleUsernameUnlock();
            if (_bioCtrl.text.isEmpty && state.profile.bio.isNotEmpty) {
              _bioCtrl.text = state.profile.bio;
            }
            if (state.profile.avatarUrl != null &&
                state.profile.avatarUrl!.isNotEmpty &&
                state.profile.avatarUrl != _avatarUrl) {
              setState(() => _avatarUrl = state.profile.avatarUrl);
            }
          } else if (state is ProfileActionSuccess) {
            Navigator.of(context).pop(true);
          } else if (state is ProfileActionFailure) {
            showAppPopup(
              context,
              content: Text(
                state.message.replaceAll('Exception: ', ''),
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
              ),
            );
          }
        },
        builder: (context, state) {
          final isSaving = state is ProfileActionInProgress;
          final isLoading = state is ProfileLoading;
          final usernameReadOnly = isSaving || !_canEditUsername;
          final unlockAt = _usernameLocked
              ? _usernameAvailableAt!.toLocal()
              : null;

          return Scaffold(
            backgroundColor: const Color(0xFFFAF9FD),
            appBar: AppBar(
              backgroundColor: const Color(0xFFFAF9FD),
              foregroundColor: const Color(0xFF292235),
              surfaceTintColor: Colors.transparent,
              leading: const BackButton(),
              title: const Text(
                'แก้ไขโปรไฟล์',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              centerTitle: false,
              elevation: 0,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar ─────────────────────────────────────────
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'เปลี่ยนรูปโปรไฟล์',
                        child: InkWell(
                          key: const ValueKey('edit-profile-avatar-picker'),
                          onTap: isSaving ? null : _pickImage,
                          customBorder: const CircleBorder(),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.gradient2,
                                      AppColors.primaryColor,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: ClipOval(
                                  child: _pickedImageBytes != null
                                      ? Image.memory(
                                          _pickedImageBytes!,
                                          fit: BoxFit.cover,
                                        )
                                      : _avatarUrl != null
                                      ? Image.network(
                                          _avatarUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: const Color(0xFFF3E8FF),
                                          child: const Icon(
                                            Icons.person_rounded,
                                            size: 48,
                                            color: AppColors.primaryColor,
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  top: 16,
                                ),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Section: ข้อมูลตัวตน ─────────────────────────
                    const EditProfileSectionTitle(title: 'ข้อมูลตัวตน'),
                    const SizedBox(height: 12),
                    EditProfileFormField(
                      controller: _displayNameCtrl,
                      label: 'ชื่อโปรไฟล์',
                      hint: 'กรอกชื่อที่ต้องการเปลี่ยน',
                      icon: Icons.badge_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'กรุณากรอกชื่อ'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    EditProfileFormField(
                      controller: _usernameCtrl,
                      label: 'ชื่อผู้ใช้',
                      hint: isLoading ? 'กำลังโหลดชื่อผู้ใช้…' : 'username',
                      icon: Icons.alternate_email_rounded,
                      readOnly: usernameReadOnly,
                      validator: usernameReadOnly ? null : _validateUsername,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      unlockAt == null
                          ? 'ใช้ A–Z, a–z, 0–9, จุด (.) และขีดล่าง (_) เปลี่ยนได้ทุก 30 วัน'
                          : 'เปลี่ยนชื่อผู้ใช้ได้อีกครั้ง ${DateFormat('d MMM yyyy เวลา HH:mm', 'th').format(unlockAt)} น.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF665D73),
                      ),
                    ),
                    const SizedBox(height: 14),
                    EditProfileFormField(
                      controller: _bioCtrl,
                      label: 'แนะนำตัว',
                      hint: 'เขียนอะไรสักอย่างเกี่ยวกับตัวคุณ...',
                      icon: Icons.info_outline_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 28),

                    // ── Save button ──────────────────────────────────
                    ElevatedButton(
                      onPressed: isSaving || isLoading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primaryColor
                            .withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'บันทึกข้อมูล',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'กรุณากรอกชื่อผู้ใช้';
    if (value.length > 100) return 'ชื่อผู้ใช้ต้องมีไม่เกิน 100 ตัวอักษร';
    if (_invalidUsernameCharacters.hasMatch(value)) {
      return 'ใช้ได้เฉพาะตัวอักษรอังกฤษ ตัวเลข จุด (.) และขีดล่าง (_)';
    }
    return null;
  }
}
