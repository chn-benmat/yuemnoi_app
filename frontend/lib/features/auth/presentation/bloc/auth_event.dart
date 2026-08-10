import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// คลาสฐานสำหรับ Event ทั้งหมดของระบบยืนยันตัวตน
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Event เมื่อผู้ใช้ต้องการเข้าสู่ระบบด้วย Email และ Password
class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

/// Event เมื่อผู้ใช้ต้องการเข้าสู่ระบบด้วยบัญชี Google
class AuthGoogleLoginRequested extends AuthEvent {
  const AuthGoogleLoginRequested();
}

/// Event เมื่อผู้ใช้ต้องการสมัครสมาชิกใหม่
class AuthRegisterRequested extends AuthEvent {
  final String displayName;
  final String email;
  final String phone;
  final String password;
  final String confirmPassword;
  final List<int>? imageBytes;
  final String? imageFileName;

  const AuthRegisterRequested({
    required this.displayName,
    required this.email,
    required this.phone,
    required this.password,
    required this.confirmPassword,
    this.imageBytes,
    this.imageFileName,
  });

  @override
  List<Object?> get props => [
        displayName,
        email,
        phone,
        password,
        confirmPassword,
        imageBytes,
        imageFileName,
      ];
}

/// Event เมื่อผู้ใช้ขอรหัส OTP (สำหรับรีเซ็ตรหัสผ่าน)
class AuthSendOtpRequested extends AuthEvent {
  final String email;

  const AuthSendOtpRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

/// Event เมื่อผู้ใช้ต้องการยืนยันรหัส OTP
class AuthVerifyOtpRequested extends AuthEvent {
  final String email;
  final String otpCode;

  const AuthVerifyOtpRequested({required this.email, required this.otpCode});

  @override
  List<Object?> get props => [email, otpCode];
}

/// Event เมื่อผู้ใช้ต้องการเปลี่ยนรหัสผ่านใหม่
class AuthChangePasswordRequested extends AuthEvent {
  final String accessToken;
  final String newPassword;

  const AuthChangePasswordRequested({
    required this.accessToken,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [accessToken, newPassword];
}

/// Event เมื่อสถานะเซสชันของ Supabase เปลี่ยนแปลง (เช่น เข้าสู่ระบบเสร็จสิ้นจาก OAuth)
class AuthAuthStateChanged extends AuthEvent {
  final Session session;

  const AuthAuthStateChanged(this.session);

  @override
  List<Object?> get props => [session];
}

/// Event สำหรับรีเซ็ตสถานะภายใน BLoC ให้กลับไปเริ่มต้นใหม่
class AuthResetState extends AuthEvent {
  const AuthResetState();
}
