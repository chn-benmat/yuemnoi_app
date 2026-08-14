import '../../domain/entities/feed_category.dart';

/// โมเดลข้อมูลหมวดหมู่ในเลเยอร์ Data
class FeedCategoryModel extends FeedCategory {
  const FeedCategoryModel({
    required super.id,
    required super.name,
    super.iconName,
  });

  factory FeedCategoryModel.fromJson(Map<String, dynamic> json) {
    return FeedCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['icon_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon_name': iconName,
    };
  }

  FeedCategory toEntity() => FeedCategory(
    id: id,
    name: name,
    iconName: iconName,
  );
}
