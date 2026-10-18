import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/feed_category.dart';

part 'feed_category_model.g.dart';

/// โมเดลข้อมูลหมวดหมู่ในเลเยอร์ Data
@JsonSerializable(fieldRename: FieldRename.snake)
class FeedCategoryModel extends FeedCategory {
  const FeedCategoryModel({
    required super.id,
    required super.name,
    super.iconName,
  });

  factory FeedCategoryModel.fromJson(Map<String, dynamic> json) =>
      _$FeedCategoryModelFromJson(json);

  Map<String, dynamic> toJson() => _$FeedCategoryModelToJson(this);

  FeedCategory toEntity() =>
      FeedCategory(id: id, name: name, iconName: iconName);
}
