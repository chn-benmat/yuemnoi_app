import 'dart:convert';

import '../../domain/entities/favorite_item.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลอุปกรณ์ที่กดถูกใจในชั้น Data
class FavoriteItemModel {
  final int id;
  final String title;
  final String ownerId;
  final String ownerName;
  final String? imageUrl;
  final double price;
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
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final title = json['item_name']?.toString() ?? 'อุปกรณ์';
    final ownerId = json['user_id']?.toString() ?? '';
    final price = (json['price'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = _extractFirstImageUrl(json['item_image_url']);
    final category = json['category']?.toString() ?? '';
    final resolvedOwnerName =
        (ownerName ?? json['owner_name']?.toString() ?? '').trim();

    return FavoriteItemModel(
      id: id,
      title: title,
      ownerId: ownerId,
      ownerName: resolvedOwnerName.isNotEmpty
          ? resolvedOwnerName
          : 'ไม่พบชื่อเจ้าของ',
      imageUrl: imageUrl,
      price: price,
      category: category,
    );
  }

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
