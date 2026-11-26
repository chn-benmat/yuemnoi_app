import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthApiException, AuthState;

import '../../../../core/network/auth_session.dart';
import '../../../../core/network/app_session_validator.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/chat_notification_service.dart';
import '../../../../core/services/favorite_service.dart';
import '../../../../core/services/user_presence_service.dart';
import '../../data/datasources/auth_remote_data_source.dart'; // สำหรับ AuthApiException
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/change_password_usecase.dart';
import '../../domain/usecases/google_login_usecase.dart';
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
  final AppSessionValidator _sessionValidator;
  StreamSubscription? _authStateSubscription;
  String? _handledAccessToken;
  Session? _accountRestoreSession;

  AuthBloc({
    required this.authRepository,
    AppSessionValidator? sessionValidator,
  }) : _sessionValidator = sessionValidator ?? AppSessionValidator(),
       super(const AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthGoogleLoginRequested>(_onGoogleLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthSendOtpRequested>(_onSendOtpRequested);
    on<AuthVerifyOtpRequested>(_onVerifyOtpRequested);
    on<AuthChangePasswordRequested>(_onChangePasswordRequested);
    on<AuthAuthStateChanged>(_onAuthStateChanged);
    on<AuthAccountRestoreDecided>(_onAccountRestoreDecided);
    on<AuthAccountDeletionRequested>(_onAccountDeletionRequested);
    on<AuthResetState>(_onResetState);

    // ติดตามการเปลี่ยนแปลงสถานะ Auth ของ Supabase
    if (SupabaseConfig.isInitialized) {
      _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange
          .listen(
            (authState) {
              if (authState.event == AuthChangeEvent.signedOut) {
                if (SupabaseConfig.client.auth.currentSession != null) return;
                _handledAccessToken = null;
                AuthSession.clear(purgeCache: true);
                UserPresenceService.instance.dispose();
                unawaited(
                  ChatNotificationService.instance.cancelAllNotifications(),
                );
              }
              if ((authState.event == AuthChangeEvent.signedIn ||
                      authState.event == AuthChangeEvent.tokenRefreshed) &&
                  authState.session != null) {
                add(
                  AuthAuthStateChanged(
                    authState.session!,
                    canRestoreAccount:
                        authState.event == AuthChangeEvent.signedIn ||
                        state is LoginLoading ||
                        state is GoogleLoginLoading,
                  ),
                );
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
    if (state is LoginLoading ||
        state is GoogleLoginLoading ||
        _accountRestoreSession != null) {
      return;
    }
    _handledAccessToken = null;
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
    if (state is GoogleLoginLoading ||
        state is LoginLoading ||
        _accountRestoreSession != null) {
      return;
    }

    if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized) {
      emit(
        const LoginFailure(
          message: 'ยังไม่ได้ตั้งค่า Supabase Publishable key สำหรับแอป',
        ),
      );
      return;
    }

    _handledAccessToken = null;
    emit(const GoogleLoginLoading());

    try {
      final started = await GoogleLoginUseCase(authRepository).execute();
      if (!started) {
        emit(const AuthInitial());
      }
    } on AuthException catch (error) {
      emit(LoginFailure(message: error.message));
    } catch (_) {
      emit(
        const LoginFailure(
          message: 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ กรุณาลองใหม่',
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
    final session = event.session;
    if (_accountRestoreSession != null ||
        _handledAccessToken == session.accessToken ||
        !_isCurrentSession(session)) {
      return;
    }
    _handledAccessToken = session.accessToken;

    try {
      await AuthSession.accept(session, validator: _sessionValidator);
    } on AccountDeletionPending catch (pending) {
      if (!_isCurrentSession(session)) return;
      if (event.canRestoreAccount) {
        _accountRestoreSession = session;
        emit(LoginNeedsAccountRestore(deleteAfter: pending.deleteAfter));
      } else {
        await _signOutLocally(userId: session.user.id);
        emit(
          const LoginFailure(message: 'กรุณาเข้าสู่ระบบใหม่เพื่อกู้คืนบัญชี'),
        );
      }
      return;
    } on AppSessionException catch (error) {
      if (!_isCurrentSession(session)) return;
      _handledAccessToken = null;
      if (error.rejected) await AuthSession.reject(userId: session.user.id);
      unawaited(FavoriteService.instance.init(forceRefresh: true));
      emit(LoginFailure(message: error.message));
      return;
    } catch (_) {
      if (!_isCurrentSession(session)) return;
      _handledAccessToken = null;
      AuthSession.clear();
      unawaited(FavoriteService.instance.init(forceRefresh: true));
      emit(
        const LoginFailure(
          message: 'ไม่สามารถตรวจสอบสิทธิ์เข้าแอปได้ กรุณาลองใหม่',
        ),
      );
      return;
    }
    _finishSignIn(session, emit);
  }

  bool _isCurrentSession(Session session) =>
      !SupabaseConfig.isInitialized ||
      SupabaseConfig.client.auth.currentSession?.accessToken ==
          session.accessToken;

  Future<void> _onAccountRestoreDecided(
    AuthAccountRestoreDecided event,
    Emitter<AuthState> emit,
  ) async {
    final candidate = _accountRestoreSession;
    if (candidate == null || state is! LoginNeedsAccountRestore) return;
    emit(const LoginLoading());
    if (!event.confirmed) {
      await _signOutLocally(userId: candidate.user.id);
      emit(const AuthInitial());
      return;
    }

    try {
      final session = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentSession
          : candidate;
      if (session == null || session.user.id != candidate.user.id) {
        throw const AppSessionException(
          'กรุณาเข้าสู่ระบบใหม่เพื่อยืนยันการกู้คืนบัญชี',
        );
      }
      await _sessionValidator.restoreAccount(session);
      await AuthSession.accept(session, validator: _sessionValidator);
      _accountRestoreSession = null;
      _handledAccessToken = session.accessToken;
      _finishSignIn(session, emit);
    } on AppSessionException catch (error) {
      await _signOutLocally(userId: candidate.user.id);
      emit(LoginFailure(message: error.message));
    } catch (_) {
      await _signOutLocally(userId: candidate.user.id);
      emit(const LoginFailure(message: 'กู้คืนบัญชีไม่สำเร็จ กรุณาลองใหม่'));
    }
  }

  Future<void> _onAccountDeletionRequested(
    AuthAccountDeletionRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AccountDeletionLoading) return;
    final token = AuthSession.accessToken;
    if (token == null) {
      emit(const AccountDeletionFailure(message: 'กรุณาเข้าสู่ระบบใหม่'));
      return;
    }
    emit(const AccountDeletionLoading());
    try {
      await authRepository.scheduleAccountDeletion(accessToken: token);
    } on AuthApiException catch (error) {
      emit(AccountDeletionFailure(message: error.message));
      return;
    } catch (_) {
      emit(
        const AccountDeletionFailure(message: 'ลบบัญชีไม่สำเร็จ กรุณาลองใหม่'),
      );
      return;
    }
    await _signOutLocally();
    emit(const AccountDeletionScheduled());
  }

  Future<void> _signOutLocally({String? userId}) async {
    await AuthSession.reject(userId: userId);
    _accountRestoreSession = null;
    _handledAccessToken = null;
    UserPresenceService.instance.dispose();
    unawaited(ChatNotificationService.instance.cancelAllNotifications());
    unawaited(FavoriteService.instance.init(forceRefresh: true));
  }

  void _finishSignIn(Session session, Emitter<AuthState> emit) {
    final isGoogle = _signedInWithGoogle(session.user.appMetadata);
    if (SupabaseConfig.isInitialized) {
      unawaited(FavoriteService.instance.init(forceRefresh: true));
      UserPresenceService.instance.initialize();
    }

    if (isGoogle) {
      emit(GoogleLoginSuccess(session: session));
      unawaited(_syncGoogleProfileImage(session.accessToken));
    } else {
      emit(LoginSuccess(session: session));
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
    if (_accountRestoreSession != null) return;
    emit(const AuthInitial());
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    _sessionValidator.close();
    authRepository.close();
    return super.close();
  }
}
