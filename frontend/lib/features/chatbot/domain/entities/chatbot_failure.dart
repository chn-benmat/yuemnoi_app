import 'package:equatable/equatable.dart';

// ข้อมูลคำขอที่ล้มเหลวสำหรับแสดงทางไปต่อ โดยไม่เดาเวลารอจากข้อความ
class ChatbotFailure extends Equatable {
  const ChatbotFailure({
    required this.messageId,
    required this.message,
    required this.isRetryable,
    this.errorCode,
    this.statusCode,
    this.retryAvailableAt,
  });

  final String messageId;
  final String message;
  final bool isRetryable;
  final String? errorCode;
  final int? statusCode;
  final DateTime? retryAvailableAt;

  bool canRetry(DateTime now) =>
      isRetryable &&
      (retryAvailableAt == null || !now.isBefore(retryAvailableAt!));

  bool get isQuota =>
      errorCode == 'providers_rate_limited' ||
      errorCode == 'quota_temporarily_unavailable' ||
      errorCode == 'quota_exhausted' ||
      statusCode == 429;

  @override
  List<Object?> get props => [
    messageId,
    message,
    isRetryable,
    errorCode,
    statusCode,
    retryAvailableAt,
  ];
}
