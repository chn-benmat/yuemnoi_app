import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/favorite_item.dart';

part 'favorite_item_model.g.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลอุปกรณ์ที่กดถูกใจในชั้น Data
@JsonSerializable(createToJson: false)
class FavoriteItemModel {
  @JsonKey(defaultValue: 0)
  final int id;
  @JsonKey(name: 'item_name', fromJson: _title)
  final String title;
  @JsonKey(name: 'user_id', fromJson: _string)
  final String ownerId;
  @JsonKey(name: '_owner_name', defaultValue: 'เจ้าของอุปกรณ์')
  final String ownerName;
  @JsonKey(name: 'item_image_url', fromJson: _extractFirstImageUrl)
  final String? imageUrl;
  final double price;
  @JsonKey(fromJson: _string)
  final String category;

  const FavoriteItemModel({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.ownerName,
    this.imageUrl,
    this.price = 0.0,
    this.category = '',
  });

  factory FavoriteItemModel.fromJson(
    Map<String, dynamic> json, {
    String? ownerName,
  }) {
    final resolvedOwnerName =
        (ownerName ?? json['owner_name']?.toString() ?? '').trim();
    return _$FavoriteItemModelFromJson({
      ...json,
      '_owner_name': resolvedOwnerName.isNotEmpty
          ? resolvedOwnerName
          : 'ไม่พบชื่อเจ้าของ',
    });
  }

  static String _title(Object? value) => value?.toString() ?? 'อุปกรณ์';
  static String _string(Object? value) => value?.toString() ?? '';

  FavoriteItem toEntity() {
    return FavoriteItem(
      id: id,
      title: title,
      ownerId: ownerId,
      ownerName: ownerName,
      imageUrl: imageUrl,
      price: price,
      category: category,
    );
  }

  static String? _extractFirstImageUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      for (final el in raw) {
        if (el != null && el.toString().trim().isNotEmpty) {
          return el.toString().trim();
        }
      }
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is List) return _extractFirstImageUrl(parsed);
        } catch (_) {}
      }
      if (trimmed.contains(',')) {
        final parts = trimmed.split(',');
        for (final p in parts) {
          if (p.trim().isNotEmpty) return p.trim();
        }
      }
      return trimmed;
    }
    return null;
  }
}
