import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

const dashboardOnlyMessage =
    'บัญชีนี้ใช้ได้เฉพาะ Dashboard สำหรับเจ้าหน้าที่ กรุณาใช้บัญชีผู้ใช้ทั่วไปในแอป';

class AppSessionException implements Exception {
  const AppSessionException(this.message, {this.rejected = false});

  final String message;
  final bool rejected;
}

class AccountDeletionPending extends AppSessionException {
  const AccountDeletionPending(this.deleteAfter)
    : super('บัญชีนี้อยู่ระหว่างรอการลบ');

  final DateTime deleteAfter;
}

class AccountDeletionExpired extends AppSessionException {
  const AccountDeletionExpired()
    : super('บัญชีนี้ครบกำหนดลบแล้ว', rejected: true);
}

class AppSessionValidator {
  AppSessionValidator({ApiClient? client}) : _client = client ?? DioApiClient();

  final ApiClient _client;

  Future<void> validate(Session session) async {
    if (session.user.appMetadata['dashboard_only'] == true) {
      throw const AppSessionException(dashboardOnlyMessage, rejected: true);
    }

    try {
      // ตรวจจาก server อีกครั้ง เพราะ app_metadata ใน session เดิมอาจยังไม่อัปเดต
      final response = await _client.get(
        '/api/auth/session',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final body = response.data;
      if (response.statusCode == 200 &&
          body is Map &&
          body['user_id'] == session.user.id) {
        return;
      }
      if (response.statusCode == 403 &&
          body is Map &&
          body['code'] == 'dashboard_only') {
        throw const AppSessionException(dashboardOnlyMessage, rejected: true);
      }
      if (response.statusCode == 409 &&
          body is Map &&
          body['code'] == 'account_deletion_pending') {
        final rawDeadline = body['delete_after'];
        final deadline = rawDeadline is String
            ? DateTime.tryParse(rawDeadline)
            : null;
        if (deadline != null) throw AccountDeletionPending(deadline);
      }
      if (response.statusCode == 410 &&
          body is Map &&
          body['code'] == 'account_deletion_expired') {
        throw const AccountDeletionExpired();
      }
      throw AppSessionException(
        response.statusCode == 401
            ? 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่'
            : 'ไม่สามารถตรวจสอบสิทธิ์เข้าแอปได้ กรุณาลองใหม่',
        rejected: response.statusCode == 401 || response.statusCode == 403,
      );
    } on ApiClientException {
      throw const AppSessionException(
        'ไม่สามารถเชื่อมต่อเพื่อตรวจสอบสิทธิ์เข้าแอปได้ กรุณาลองใหม่',
      );
    }
  }

  Future<void> restoreAccount(Session session) async {
    try {
      final response = await _client.post(
        '/api/auth/account/restore',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final body = response.data;
      if (response.statusCode == 200 &&
          body is Map &&
          body['user_id'] == session.user.id) {
        return;
      }
      if (response.statusCode == 410 &&
          body is Map &&
          body['code'] == 'account_deletion_expired') {
        throw const AccountDeletionExpired();
      }
      if (response.statusCode == 401) {
        throw const AppSessionException(
          'กรุณาเข้าสู่ระบบใหม่เพื่อยืนยันการกู้คืนบัญชี',
          rejected: true,
        );
      }
      throw const AppSessionException('กู้คืนบัญชีไม่สำเร็จ กรุณาลองใหม่');
    } on ApiClientException {
      throw const AppSessionException(
        'ไม่สามารถเชื่อมต่อเพื่อกู้คืนบัญชีได้ กรุณาลองใหม่',
      );
    }
  }

  void close() => _client.close();
}
