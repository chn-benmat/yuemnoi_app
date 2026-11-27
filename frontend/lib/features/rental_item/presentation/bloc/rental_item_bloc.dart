import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/item_catalog_service.dart';
import '../../../identity/domain/rental_verification.dart';
import '../../domain/repositories/rental_item_repository.dart';
import '../../domain/usecases/create_rental_item_usecase.dart';
import 'rental_item_event.dart';
import 'rental_item_state.dart';

class RentalItemBloc extends Bloc<RentalItemEvent, RentalItemState> {
  RentalItemBloc({required CreateRentalItemUseCase createItem})
    : _createItem = createItem,
      super(const RentalItemState()) {
    on<RentalItemImagesAdded>(_onImagesAdded);
    on<RentalItemImageRemoved>(_onImageRemoved);
    on<RentalItemSubmitted>(_onSubmitted);
  }

  static const minImages = 1;
  static const maxImages = 5;
  final CreateRentalItemUseCase _createItem;

  void _onImagesAdded(
    RentalItemImagesAdded event,
    Emitter<RentalItemState> emit,
  ) {
    final remaining = maxImages - state.images.length;
    if (remaining <= 0) return;
    emit(
      state.copyWith(
        images: [...state.images, ...event.images.take(remaining)],
      ),
    );
  }

  void _onImageRemoved(
    RentalItemImageRemoved event,
    Emitter<RentalItemState> emit,
  ) {
    if (event.index < 0 || event.index >= state.images.length) return;
    final images = [...state.images]..removeAt(event.index);
    emit(state.copyWith(images: images));
  }

  Future<void> _onSubmitted(
    RentalItemSubmitted event,
    Emitter<RentalItemState> emit,
  ) async {
    if (state.status == RentalItemSubmissionStatus.submitting) return;

    final imageCount = event.draft.images.length;
    if (imageCount < minImages || imageCount > maxImages) {
      emit(
        state.copyWith(
          status: RentalItemSubmissionStatus.failure,
          clearError: true,
          errorMessage: imageCount < minImages
              ? 'กรุณาเพิ่มรูปภาพอย่างน้อย $minImages รูป'
              : 'เพิ่มรูปภาพได้ไม่เกิน $maxImages รูป',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: RentalItemSubmissionStatus.submitting,
        clearError: true,
      ),
    );
    try {
      final item = await _createItem.execute(event.draft);
      emit(
        state.copyWith(
          status: RentalItemSubmissionStatus.success,
          createdItem: item,
        ),
      );
      ItemCatalogService.instance.notifyChanged();
    } on RentalVerificationRequired catch (error) {
      emit(
        state.copyWith(
          status: RentalItemSubmissionStatus.failure,
          verification: error.verification,
        ),
      );
    } on RentalItemException catch (error) {
      emit(
        state.copyWith(
          status: RentalItemSubmissionStatus.failure,
          errorMessage: error.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: RentalItemSubmissionStatus.failure,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _createItem.close();
    return super.close();
  }
}
