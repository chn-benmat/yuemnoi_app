import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/services/app_permission_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../bloc/profile_cubit.dart';
import '../../bloc/profile_state.dart';
import '../../widgets/account/edit_profile_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  late final ProfileCubit _cubit;

  String? _avatarUrl;
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;

  @override
  void initState() {
    super.initState();
    _cubit = ProfileCubit();

    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;
    final meta = user?.userMetadata ?? {};

    _displayNameCtrl = TextEditingController(
      text:
          (meta['display_name'] ??
                  meta['full_name'] ??
                  user?.email?.split('@').first ??
                  '')
              .toString(),
    );
    _usernameCtrl = TextEditingController(
      text: (meta['username'] ?? user?.email?.split('@').first ?? '')
          .toString(),
    );
    _bioCtrl = TextEditingController(text: (meta['bio'] ?? '').toString());
    _avatarUrl = (meta['avatar_url'] ?? meta['picture'] ?? '').toString();
    if (_avatarUrl!.isEmpty) _avatarUrl = null;

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final userId = user?.id ?? '';
    if (userId.isNotEmpty) {
      _cubit.loadProfile(userId: userId, accessToken: session?.accessToken);
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _cubit.close();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณาเข้าสู่ระบบก่อน'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    await _cubit.updateProfileData(
      accessToken: accessToken,
      displayName: _displayNameCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      imageBytes: _pickedImageBytes,
      imageName: _pickedImageName,
    );
  }

  Future<void> _editRecommendationLocation() async {
    await AppRoutes.openRecommendationLocationSettings(context);
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
            if (_usernameCtrl.text.isEmpty &&
                state.profile.username.isNotEmpty) {
              _usernameCtrl.text = state.profile.username;
            }
            if (_bioCtrl.text.isEmpty && state.profile.bio.isNotEmpty) {
              _bioCtrl.text = state.profile.bio;
            }
            if (_avatarUrl == null && state.profile.avatarUrl != null) {
              setState(() => _avatarUrl = state.profile.avatarUrl);
            }
          } else if (state is ProfileActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.message,
                  style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
                ),
                backgroundColor: AppColors.primaryColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
            Navigator.of(context).pop(true);
          } else if (state is ProfileActionFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.message.replaceAll('Exception: ', ''),
                  style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          final isSaving = state is ProfileActionInProgress;

          return Scaffold(
            backgroundColor: const Color(0xFFF7F7F9),
            appBar: AppBar(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              leading: const BackButton(),
              title: const Text(
                'แก้ไขโปรไฟล์',
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
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar ─────────────────────────────────────────
                    Center(
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
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Section: ข้อมูลตัวตน ─────────────────────────
                    const EditProfileSectionTitle(title: 'ข้อมูลตัวตน'),
                    const SizedBox(height: 12),
                    EditProfileFormField(
                      controller: _displayNameCtrl,
                      label: 'ชื่อแสดงตัวตน',
                      hint: 'กรอกชื่อที่ต้องการแสดง',
                      icon: Icons.badge_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'กรุณากรอกชื่อ'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    EditProfileFormField(
                      controller: _usernameCtrl,
                      label: 'ชื่อผู้ใช้',
                      hint: 'username',
                      icon: Icons.alternate_email_rounded,
                    ),
                    const SizedBox(height: 14),
                    EditProfileFormField(
                      controller: _bioCtrl,
                      label: 'ชีวประวัติ / แนะนำตัว',
                      hint: 'เขียนอะไรสักอย่างเกี่ยวกับตัวคุณ...',
                      icon: Icons.info_outline_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 22),
                    const EditProfileSectionTitle(title: 'ตำแหน่งแนะนำสินค้า'),
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        onTap: _editRecommendationLocation,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primaryColor,
                        ),
                        title: const Text(
                          'เปลี่ยนตำแหน่งของฉัน',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'จัดการตำแหน่งที่ใช้คำนวณระยะและแนะนำอุปกรณ์ใกล้คุณ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Save button ──────────────────────────────────
                    ElevatedButton(
                      onPressed: isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primaryColor
                            .withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
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
}
