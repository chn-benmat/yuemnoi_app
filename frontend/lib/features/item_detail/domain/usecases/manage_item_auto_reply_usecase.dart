import '../entities/item_auto_reply.dart';
import '../repositories/item_auto_reply_repository.dart';

class ManageItemAutoReplyUseCase {
  const ManageItemAutoReplyUseCase(this.repository);
  final ItemAutoReplyRepository repository;

  Future<ItemAutoReply> load(int itemId) => repository.load(itemId);

  Future<ItemAutoReply> save(int itemId, ItemAutoReply draft) {
    final message = draft.message.trim();
    if (message.runes.length > 500) {
      throw const ItemAutoReplyException(
        'ข้อความตอบกลับต้องไม่เกิน 500 ตัวอักษร',
      );
    }
    if (draft.enabled && message.isEmpty) {
      throw const ItemAutoReplyException(
        'กรุณาพิมพ์ข้อความก่อนเปิดการตอบกลับอัตโนมัติ',
      );
    }
    return repository.save(
      itemId,
      ItemAutoReply(enabled: draft.enabled, message: message),
    );
  }
}
