import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthApiException, AuthState;

import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/chat_notification_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/user_presence_service.dart';
import '../../data/datasources/auth_remote_data_source.dart'; // สำหรับ AuthApiException
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/change_password_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import '../../domain/usecases/send_otp_usecase.dart';
import '../../domain/usecases/sync_google_profile_image_usecase.dart';
import '../../domain/usecases/verify_otp_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// BLoC จัดการข้อมูลและการโต้ตอบต่างๆ ในส่วนของการยืนยันตัวตน
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;
  StreamSubscription? _authStateSubscription;
  bool _signInHandled = false;

  AuthBloc({required this.authRepository}) : super(const AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthGoogleLoginRequested>(_onGoogleLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthSendOtpRequested>(_onSendOtpRequested);
    on<AuthVerifyOtpRequested>(_onVerifyOtpRequested);
    on<AuthChangePasswordRequested>(_onChangePasswordRequested);
    on<AuthAuthStateChanged>(_onAuthStateChanged);
    on<AuthResetState>(_onResetState);

    // ติดตามการเปลี่ยนแปลงสถานะ Auth ของ Supabase
    if (SupabaseConfig.isInitialized) {
      _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange
          .listen(
            (authState) {
              if (authState.event == AuthChangeEvent.signedIn &&
                  authState.session != null) {
                add(AuthAuthStateChanged(authState.session!));
              }
            },
            onError: (error) {
              // สามารถดักจับ error เพิ่มเติมได้ตรงนี้
            },
          );
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    _signInHandled = false;
    emit(const LoginLoading());
    try {
      final tokens = await LoginUseCase(
        authRepository,
      ).execute(email: event.email, password: event.password);

      final authResponse = await SupabaseConfig.client.auth.setSession(
        tokens.refreshToken,
        accessToken: tokens.accessToken,
      );

      final session = authResponse.session;
      if (session == null) {
        emit(const LoginFailure(message: 'ไม่สามารถบันทึก Session ได้'));
      }
      // หมายเหตุ: การนำทางจะสำเร็จผ่านการทำงานของ listener ที่ยิง AuthAuthStateChanged เสมอ
    } on AuthApiException catch (error) {
      emit(LoginFailure(message: error.message));
    } on AuthException catch (error) {
      emit(LoginFailure(message: error.message));
    } catch (error) {
      emit(LoginFailure(message: error.toString()));
    }
  }

  Future<void> _onGoogleLoginRequested(
    AuthGoogleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized) {
      emit(
        const LoginFailure(
          message: 'ยังไม่ได้ตั้งค่า Supabase Publishable key สำหรับแอป',
        ),
      );
      return;
    }

    _signInHandled = false;
    emit(const GoogleLoginLoading());

    try {
      final launched = await SupabaseConfig.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirectUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );

      if (!launched) {
        emit(
          const LoginFailure(message: 'ไม่สามารถเปิดหน้าล็อกอิน Google ได้'),
        );
      }
    } on AuthException catch (error) {
      emit(LoginFailure(message: error.message));
    } catch (_) {
      emit(
        const LoginFailure(
          message: 'เกิดข้อผิดพลาดระหว่างเปิด Google Login กรุณาลองใหม่',
        ),
      );
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const RegisterLoading());
    try {
      await RegisterUseCase(authRepository).execute(
        displayName: event.displayName,
        email: event.email,
        phone: event.phone,
        password: event.password,
        confirmPassword: event.confirmPassword,
        imageBytes: event.imageBytes,
        imageFileName: event.imageFileName,
      );
      emit(const RegisterSuccess());
    } on AuthApiException catch (error) {
      emit(RegisterFailure(message: error.message));
    } catch (error) {
      emit(RegisterFailure(message: error.toString()));
    }
  }

  Future<void> _onSendOtpRequested(
    AuthSendOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const SendOtpLoading());
    try {
      await SendOtpUseCase(authRepository).execute(email: event.email);
      emit(const SendOtpSuccess());
    } on AuthApiException catch (error) {
      emit(SendOtpFailure(message: error.message));
    } catch (error) {
      emit(SendOtpFailure(message: error.toString()));
    }
  }

  Future<void> _onVerifyOtpRequested(
    AuthVerifyOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const VerifyOtpLoading());
    try {
      final tokens = await VerifyOtpUseCase(
        authRepository,
      ).execute(email: event.email, otpCode: event.otpCode);
      emit(VerifyOtpSuccess(tokens: tokens));
    } on AuthApiException catch (error) {
      emit(VerifyOtpFailure(message: error.message));
    } catch (error) {
      emit(VerifyOtpFailure(message: error.toString()));
    }
  }

  Future<void> _onChangePasswordRequested(
    AuthChangePasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const ChangePasswordLoading());
    try {
      await ChangePasswordUseCase(
        authRepository,
      ).execute(accessToken: event.accessToken, newPassword: event.newPassword);
      emit(const ChangePasswordSuccess());
    } on AuthApiException catch (error) {
      emit(ChangePasswordFailure(message: error.message));
    } catch (error) {
      emit(ChangePasswordFailure(message: error.toString()));
    }
  }

  Future<void> _onAuthStateChanged(
    AuthAuthStateChanged event,
    Emitter<AuthState> emit,
  ) async {
    if (_signInHandled) return;
    _signInHandled = true;

    AuthSession.saveAccessToken(event.session.accessToken);
    final isGoogle = _signedInWithGoogle(event.session.user.appMetadata);

    UserPresenceService.instance.initialize();
    unawaited(ChatNotificationService.instance.initialize());
    final userId = event.session.user.id;
    if (userId.isNotEmpty) {
      unawaited(FcmService.instance.syncUserToken(userId));
    }

    if (isGoogle) {
      emit(GoogleLoginSuccess(session: event.session));
      unawaited(_syncGoogleProfileImage(event.session.accessToken));
    } else {
      emit(LoginSuccess(session: event.session));
    }
  }

  Future<void> _syncGoogleProfileImage(String accessToken) async {
    try {
      await SyncGoogleProfileImageUseCase(
        authRepository,
      ).execute(accessToken: accessToken);
    } catch (_) {
      // การ sync รูปเป็นงานเสริมและต้องไม่ทำให้ session ที่ล็อกอินสำเร็จล้มเหลว
    }
  }

  bool _signedInWithGoogle(Map<String, dynamic> appMetadata) {
    if (appMetadata['provider'] == 'google') return true;
    final providers = appMetadata['providers'];
    return providers is List && providers.contains('google');
  }

  void _onResetState(AuthResetState event, Emitter<AuthState> emit) {
    _signInHandled = false;
    emit(const AuthInitial());
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    authRepository.close();
    return super.close();
  }
}
