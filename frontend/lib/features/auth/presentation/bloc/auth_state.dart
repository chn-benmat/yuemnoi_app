import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/auth_tokens.dart';

/// คลาสฐานสำหรับ State ทั้งหมดของระบบยืนยันตัวตน
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// สถานะเริ่มต้น
class AuthInitial extends AuthState {
  const AuthInitial();
}

// --- Login States ---

/// กำลังดำเนินการเข้าสู่ระบบด้วยอีเมล/รหัสผ่าน
class LoginLoading extends AuthState {
  const LoginLoading();
}

/// เข้าสู่ระบบด้วยอีเมล/รหัสผ่าน สำเร็จ
class LoginSuccess extends AuthState {
  final Session session;

  const LoginSuccess({required this.session});

  @override
  List<Object?> get props => [session];
}

/// เข้าสู่ระบบด้วยอีเมล/รหัสผ่าน ล้มเหลว
class LoginFailure extends AuthState {
  final String message;

  const LoginFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

class LoginNeedsAccountRestore extends AuthState {
  const LoginNeedsAccountRestore({required this.deleteAfter});

  final DateTime deleteAfter;

  @override
  List<Object?> get props => [deleteAfter];
}

class AccountDeletionLoading extends AuthState {
  const AccountDeletionLoading();
}

class AccountDeletionFailure extends AuthState {
  const AccountDeletionFailure({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class AccountDeletionScheduled extends AuthState {
  const AccountDeletionScheduled();
}

// --- Google Login States ---

/// กำลังดำเนินการเข้าสู่ระบบด้วย Google
class GoogleLoginLoading extends AuthState {
  const GoogleLoginLoading();
}

/// เข้าสู่ระบบด้วย Google สำเร็จ
class GoogleLoginSuccess extends AuthState {
  final Session session;

  const GoogleLoginSuccess({required this.session});

  @override
  List<Object?> get props => [session];
}

// --- Register States ---

/// กำลังดำเนินการสมัครสมาชิก
class RegisterLoading extends AuthState {
  const RegisterLoading();
}

/// รับคำขอสมัครแล้วและรอผู้ใช้ยืนยันอีเมล
class RegisterSuccess extends AuthState {
  final String email;

  const RegisterSuccess({required this.email});

  @override
  List<Object?> get props => [email];
}

/// สมัครสมาชิกไม่สำเร็จ
class RegisterFailure extends AuthState {
  final String message;

  const RegisterFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

// --- OTP States ---

/// กำลังดำเนินการส่งรหัส OTP
class SendOtpLoading extends AuthState {
  const SendOtpLoading();
}

/// ส่งรหัส OTP สำเร็จ
class SendOtpSuccess extends AuthState {
  const SendOtpSuccess();
}

/// ส่งรหัส OTP ไม่สำเร็จ
class SendOtpFailure extends AuthState {
  final String message;

  const SendOtpFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

/// กำลังดำเนินการยืนยันรหัส OTP
class VerifyOtpLoading extends AuthState {
  const VerifyOtpLoading();
}

/// ยืนยันรหัส OTP สำเร็จ
class VerifyOtpSuccess extends AuthState {
  final AuthTokens tokens;

  const VerifyOtpSuccess({required this.tokens});

  @override
  List<Object?> get props => [tokens];
}

/// ยืนยันรหัส OTP ไม่สำเร็จ
class VerifyOtpFailure extends AuthState {
  final String message;

  const VerifyOtpFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

// --- Change Password States ---

/// กำลังดำเนินการเปลี่ยนรหัสผ่าน
class ChangePasswordLoading extends AuthState {
  const ChangePasswordLoading();
}

/// เปลี่ยนรหัสผ่านสำเร็จ
class ChangePasswordSuccess extends AuthState {
  const ChangePasswordSuccess();
}

/// เปลี่ยนรหัสผ่านไม่สำเร็จ
class ChangePasswordFailure extends AuthState {
  final String message;

  const ChangePasswordFailure({required this.message});

  @override
  List<Object?> get props => [message];
}
