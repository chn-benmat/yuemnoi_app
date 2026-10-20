import 'package:equatable/equatable.dart';

class RelatedItem extends Equatable {
  const RelatedItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.rentalType,
    this.imageUrl = '',
  });

  final int id;
  final String name;
  final String category;
  final int price;
  final String rentalType;
  final String imageUrl;

  String get unitLabel => rentalType == 'รายชั่วโมง' ? 'ชั่วโมง' : 'วัน';

  @override
  List<Object?> get props => [id, name, category, price, rentalType, imageUrl];
}
