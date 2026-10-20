import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../models/user_profile_model.dart';

// คำอธิบาย: Exception สำหรับข้อผิดพลาดใน Profile Data Source
class ProfileApiException implements Exception {
  const ProfileApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

// คำอธิบาย: Data Source จัดการติดต่อกับ Backend API และ Supabase สำหรับข้อมูลโปรไฟล์
class ProfileRemoteDataSource {
  final ApiClient _client;

  ProfileRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  Future<UserProfileModel> getProfile({
    required String userId,
    String? accessToken,
  }) async {
    final Map<String, dynamic> mergedData = {'user_id': userId};

    // 1. ดึงข้อมูลจาก Backend API ถ้ามี accessToken
    if (accessToken != null && accessToken.isNotEmpty) {
      try {
        final response = await _client.get(
          '/api/user/profile',
          headers: {'Authorization': 'Bearer $accessToken'},
        );
        if (response.statusCode == 200 && response.data is Map) {
          mergedData.addAll(Map<String, dynamic>.from(response.data as Map));
        }
      } catch (_) {}
    }

    // 2. ดึงข้อมูลจาก Supabase profile_tb
    if (SupabaseConfig.isInitialized) {
      try {
        final profileResp = await SupabaseConfig.client
            .schema('profiles')
            .from('profile_tb')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        if (profileResp != null) {
          mergedData.addAll(Map<String, dynamic>.from(profileResp));
        }
      } catch (_) {}

      // 3. ถ้าเป็นผู้ใช้ปัจจุบัน นำ metadata จาก Auth มาเสริม
      try {
        final currentUser = SupabaseConfig.client.auth.currentUser;
        if (currentUser != null && currentUser.id == userId) {
          final meta = currentUser.userMetadata ?? {};
          final name =
              meta['display_name'] as String? ??
              meta['full_name'] as String? ??
              currentUser.email?.split('@').first;
          if (name != null &&
              name.isNotEmpty &&
              (mergedData['display_name'] == null ||
                  mergedData['display_name'].toString().isEmpty)) {
            mergedData['display_name'] = name;
          }
          if (currentUser.email != null &&
              (mergedData['email'] == null ||
                  mergedData['email'].toString().isEmpty)) {
            mergedData['email'] = currentUser.email;
          }
          final bio = meta['bio'] as String?;
          if (bio != null &&
              bio.isNotEmpty &&
              (mergedData['bio'] == null ||
                  mergedData['bio'].toString().isEmpty)) {
            mergedData['bio'] = bio;
          }
          final avatar =
              meta['avatar_url'] as String? ?? meta['picture'] as String?;
          if (avatar != null &&
              avatar.isNotEmpty &&
              (mergedData['user_image_url'] == null ||
                  mergedData['user_image_url'].toString().isEmpty)) {
            mergedData['user_image_url'] = avatar;
          }
        }
      } catch (_) {}
    }

    return UserProfileModel.fromJson(mergedData);
  }

  Future<UserProfileModel> updateProfile({
    required String accessToken,
    String? displayName,
    String? username,
    String? bio,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    final headers = {'Authorization': 'Bearer $accessToken'};
    ApiResponse response;

    try {
      final Map<String, String> fields = {};
      if (displayName != null) fields['display_name'] = displayName;
      if (username != null) fields['username'] = username;
      if (bio != null) fields['bio'] = bio;

      if (imageBytes != null && imageName != null) {
        response = await _client.putMultipart(
          '/api/user/profile',
          headers: headers,
          fields: fields,
          files: [
            ApiUpload(
              fieldName: 'image',
              bytes: imageBytes,
              fileName: imageName,
            ),
          ],
        );
      } else {
        response = await _client.put(
          '/api/user/profile',
          headers: headers,
          data: fields,
        );
      }
    } on ApiClientException catch (e) {
      throw ProfileApiException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.type}');
    } catch (e) {
      if (e is ProfileApiException) rethrow;
      throw ProfileApiException(e.toString());
    }

    if (response.statusCode != 200) {
      final errorMsg = response.data is Map
          ? response.data['error']?.toString()
          : null;
      throw ProfileApiException(errorMsg ?? 'ไม่สามารถบันทึกข้อมูลโปรไฟล์ได้');
    }

    // อัปเดตข้อมูลไปยัง Supabase User Metadata เพื่อความสอดคล้อง
    if (SupabaseConfig.isInitialized) {
      try {
        final Map<String, dynamic> metaData = {};
        if (displayName != null) metaData['display_name'] = displayName;
        if (bio != null) metaData['bio'] = bio;

        if (metaData.isNotEmpty) {
          await SupabaseConfig.client.auth.updateUser(
            UserAttributes(data: metaData),
          );
        }
      } catch (_) {}
    }

    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    return UserProfileModel.fromJson(data);
  }

  Future<void> updateContactPhone({
    required String accessToken,
    required String phone,
  }) async {
    final headers = {'Authorization': 'Bearer $accessToken'};
    try {
      final response = await _client.put(
        '/api/user/contact',
        headers: headers,
        data: {'phone': phone},
      );
      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : null;
        throw ProfileApiException(
          errorMsg ?? 'ไม่สามารถบันทึกเบอร์โทรศัพท์ได้',
        );
      }

      if (SupabaseConfig.isInitialized) {
        try {
          await SupabaseConfig.client.auth.updateUser(
            UserAttributes(data: {'phone': phone}),
          );
        } catch (_) {}
      }
    } on ApiClientException catch (e) {
      throw ProfileApiException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.type}');
    } catch (e) {
      if (e is ProfileApiException) rethrow;
      throw ProfileApiException(e.toString());
    }
  }

  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  }) async {
    final headers = {'Authorization': 'Bearer $accessToken'};
    try {
      final response = await _client.post(
        '/api/auth/change-password',
        headers: headers,
        data: {'new_password': newPassword},
      );

      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : null;
        throw ProfileApiException(errorMsg ?? 'ไม่สามารถเปลี่ยนรหัสผ่านได้');
      }

      if (SupabaseConfig.isInitialized) {
        try {
          await SupabaseConfig.client.auth.updateUser(
            UserAttributes(password: newPassword),
          );
        } catch (_) {}
      }
    } on ApiClientException catch (e) {
      throw ProfileApiException('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: ${e.type}');
    } catch (e) {
      if (e is ProfileApiException) rethrow;
      throw ProfileApiException(e.toString());
    }
  }
}
