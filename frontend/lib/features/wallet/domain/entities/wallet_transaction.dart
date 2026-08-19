import 'package:equatable/equatable.dart';

class WalletTransaction extends Equatable {
  final String id;
  final String title;
  final double amount;
  final DateTime dateTime;
  final String type; // 'top_up', 'withdraw', etc.
  final String status;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.dateTime,
    this.type = 'top_up',
    this.status = 'เสร็จสิ้น',
  });

  String get formattedDateThai {
    const thaiMonths = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = thaiMonths[dateTime.month - 1];
    final yearThai = dateTime.year + 543;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day $month $yearThai - $hour:$minute';
  }

  @override
  List<Object?> get props => [id, title, amount, dateTime, type, status];
}
