import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/models/chat_conversation_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';

void main() {
  ChatConversation openConversation(String userId, {String? itemOwnerId}) {
    return ChatConversationModel.fromRecords(
      conversation: const {
        'id': 'shared-room',
        'renter_id': 'original-renter',
        'owner_id': 'original-owner',
        'item_id': 42,
      },
      otherProfile: null,
      item: itemOwnerId == null ? null : {'id': 42, 'user_id': itemOwnerId},
      currentUserId: userId,
    );
  }

  test('uses the current item owner when a chat is reused in reverse', () {
    final owner = openConversation(
      'original-renter',
      itemOwnerId: 'original-renter',
    );
    final renter = openConversation(
      'original-owner',
      itemOwnerId: 'original-renter',
    );

    expect(owner.currentUserRentalRole, ChatParticipantRole.owner);
    expect(renter.currentUserRentalRole, ChatParticipantRole.renter);
    expect(
      owner.copyWith(name: 'ลูกค้า').currentUserRentalRole,
      ChatParticipantRole.owner,
    );
  });

  test('uses the saved participant roles when the item is unavailable', () {
    expect(
      openConversation('original-owner').currentUserRentalRole,
      ChatParticipantRole.owner,
    );
    expect(
      openConversation('original-renter').currentUserRentalRole,
      ChatParticipantRole.renter,
    );
  });
}
