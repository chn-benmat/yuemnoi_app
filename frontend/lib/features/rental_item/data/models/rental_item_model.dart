import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/rental_item.dart';

part 'rental_item_model.g.dart';

@JsonSerializable(createToJson: false)
class RentalItemModel {
  const RentalItemModel({required this.id, required this.imageUrls});

  factory RentalItemModel.fromJson(Map<String, dynamic> json) =>
      _$RentalItemModelFromJson(json);

  @JsonKey(fromJson: _id)
  final int id;
  @JsonKey(name: 'item_image_url', fromJson: _imageUrls)
  final List<String> imageUrls;

  static int _id(Object? value) {
    if (value is! num) throw const FormatException('Invalid item id');
    return value.toInt();
  }

  static List<String> _imageUrls(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  RentalItem toEntity() => RentalItem(id: id, imageUrls: imageUrls);
}
