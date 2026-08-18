import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// บริการจัดการปักหมุดห้องแชท (จำกัดปักหมุดได้สูงสุด 1 ห้องแชทไว้บนสุด)
class ChatPinService {
  ChatPinService._();
  static final ChatPinService instance = ChatPinService._();

  static const String _key = 'yuemnoi_pinned_chat_id';
  String? _pinnedConversationId;
  final ValueNotifier<String?> pinNotifier = ValueNotifier<String?>(null);

  String? get pinnedConversationId => _pinnedConversationId;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pinnedConversationId = prefs.getString(_key);
      pinNotifier.value = _pinnedConversationId;
    } catch (_) {}
  }

  bool isPinned(String conversationId) {
    return _pinnedConversationId == conversationId;
  }

  Future<void> togglePin(String conversationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pinnedConversationId == conversationId) {
        _pinnedConversationId = null;
        await prefs.remove(_key);
      } else {
        _pinnedConversationId = conversationId;
        await prefs.setString(_key, conversationId);
      }
      pinNotifier.value = _pinnedConversationId;
    } catch (_) {
      if (_pinnedConversationId == conversationId) {
        _pinnedConversationId = null;
      } else {
        _pinnedConversationId = conversationId;
      }
      pinNotifier.value = _pinnedConversationId;
    }
  }

  Future<void> unpin(String conversationId) async {
    if (_pinnedConversationId == conversationId) {
      await togglePin(conversationId);
    }
  }
}
