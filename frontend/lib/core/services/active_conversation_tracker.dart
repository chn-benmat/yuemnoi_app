class ActiveConversationTracker {
  ActiveConversationTracker._();

  static final ActiveConversationTracker instance =
      ActiveConversationTracker._();

  final List<String> _activeConversations = [];

  String? get activeConversationId => _activeConversations.lastOrNull;

  bool isConversationActive(String conversationId) {
    return activeConversationId == conversationId;
  }

  void setActive(String conversationId) {
    _activeConversations.add(conversationId);
  }

  void clearActive([String? conversationId]) {
    if (conversationId == null) {
      _activeConversations.clear();
      return;
    }
    final index = _activeConversations.lastIndexOf(conversationId);
    if (index >= 0) _activeConversations.removeAt(index);
  }
}
