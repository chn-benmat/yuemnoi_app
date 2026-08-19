class ActiveConversationTracker {
  ActiveConversationTracker._();

  static final ActiveConversationTracker instance =
      ActiveConversationTracker._();

  String? _activeConversationId;

  String? get activeConversationId => _activeConversationId;

  bool isConversationActive(String conversationId) {
    return _activeConversationId == conversationId;
  }

  void setActive(String conversationId) {
    _activeConversationId = conversationId;
  }

  void clearActive([String? conversationId]) {
    if (conversationId == null || _activeConversationId == conversationId) {
      _activeConversationId = null;
    }
  }
}
