import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/profile_storefront.dart';
import '../../domain/usecases/get_profile_storefront_usecase.dart';

class ProfileStorefrontState {
  const ProfileStorefrontState({
    this.data,
    this.isLoading = false,
    this.hasError = false,
  });

  final ProfileStorefront? data;
  final bool isLoading;
  final bool hasError;
}

class ProfileStorefrontCubit extends Cubit<ProfileStorefrontState> {
  ProfileStorefrontCubit({required this.userId, required this.getStorefront})
    : super(const ProfileStorefrontState(isLoading: true));

  final String userId;
  final GetProfileStorefrontUseCase getStorefront;
  Future<void>? _pending;

  Future<void> load() {
    if (isClosed) return Future.value();
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    emit(ProfileStorefrontState(data: state.data, isLoading: true));
    try {
      final data = await getStorefront.execute(userId);
      if (!isClosed) emit(ProfileStorefrontState(data: data));
    } catch (_) {
      if (!isClosed) {
        emit(ProfileStorefrontState(data: state.data, hasError: true));
      }
    }
  }
}
