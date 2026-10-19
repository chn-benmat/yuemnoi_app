import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/item_auto_reply.dart';
import '../../domain/usecases/manage_item_auto_reply_usecase.dart';

class ItemAutoReplyState {
  const ItemAutoReplyState({
    this.loading = true,
    this.saving = false,
    this.saved,
    this.draft = const ItemAutoReply(),
    this.error,
    this.justSaved = false,
  });
  final bool loading;
  final bool saving;
  final ItemAutoReply? saved;
  final ItemAutoReply draft;
  final String? error;
  final bool justSaved;
  bool get dirty => saved != null && saved != draft;
}

class ItemAutoReplyCubit extends Cubit<ItemAutoReplyState> {
  ItemAutoReplyCubit({required this.itemId, required this.manage})
    : super(const ItemAutoReplyState());
  final int itemId;
  final ManageItemAutoReplyUseCase manage;

  Future<void> load() async {
    emit(const ItemAutoReplyState());
    try {
      final settings = await manage.load(itemId);
      if (!isClosed)
        emit(
          ItemAutoReplyState(loading: false, saved: settings, draft: settings),
        );
    } catch (error) {
      if (!isClosed)
        emit(ItemAutoReplyState(loading: false, error: _message(error)));
    }
  }

  void change({bool? enabled, String? message}) {
    if (state.loading || state.saving || state.saved == null) return;
    emit(
      ItemAutoReplyState(
        loading: false,
        saved: state.saved,
        draft: ItemAutoReply(
          enabled: enabled ?? state.draft.enabled,
          message: message ?? state.draft.message,
        ),
      ),
    );
  }

  Future<void> save() async {
    if (!state.dirty || state.saving) return;
    final previous = state;
    emit(
      ItemAutoReplyState(
        loading: false,
        saving: true,
        saved: previous.saved,
        draft: previous.draft,
      ),
    );
    try {
      final settings = await manage.save(itemId, previous.draft);
      if (!isClosed)
        emit(
          ItemAutoReplyState(
            loading: false,
            saved: settings,
            draft: settings,
            justSaved: true,
          ),
        );
    } catch (error) {
      if (!isClosed)
        emit(
          ItemAutoReplyState(
            loading: false,
            saved: previous.saved,
            draft: previous.draft,
            error: _message(error),
          ),
        );
    }
  }

  String _message(Object error) => error is ItemAutoReplyException
      ? error.message
      : 'เชื่อมต่อระบบไม่สำเร็จ กรุณาลองใหม่';
}
