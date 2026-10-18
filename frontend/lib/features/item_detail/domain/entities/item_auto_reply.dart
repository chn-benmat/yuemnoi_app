import 'package:equatable/equatable.dart';

class ItemAutoReply extends Equatable {
  const ItemAutoReply({this.enabled = false, this.message = ''});
  final bool enabled;
  final String message;

  @override
  List<Object?> get props => [enabled, message];
}

class ItemAutoReplyException implements Exception {
  const ItemAutoReplyException(this.message);
  final String message;
}
