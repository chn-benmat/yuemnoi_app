import 'dart:convert';

import '../../domain/entities/user_item.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลอุปกรณ์ของผู้ใช้จาก item_tb ในชั้น Data
class UserItemModel {
  final int? id;
  final String title;
  final String subtitle;
  final double price;
  final int imageCount;
  final String? imageUrl;
  final String category;

  const UserItemModel({
    this.id,
    required this.title,
    required this.subtitle,
    this.price = 0.0,
    this.imageCount = 1,
    this.imageUrl,
    this.category = 'ทั่วไป',
  });

  factory UserItemModel.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final title = json['item_name']?.toString() ?? 'อุปกรณ์';
    final cat = json['category']?.toString() ?? 'ทั่วไป';
    final desc = json['description']?.toString() ?? '';
    final price = (json['price'] as num?)?.toDouble() ?? 0.0;
    final rawImages = json['item_image_url'];
    final imageUrl = _extractFirstImageUrl(rawImages);
    final count = _extractImageCount(rawImages);

    return UserItemModel(
      id: id,
      title: title,
      subtitle: desc.isNotEmpty ? desc : 'หมวดหมู่: $cat',
      price: price,
      imageCount: count > 0 ? count : 1,
      imageUrl: imageUrl,
      category: cat,
    );
  }

  UserItem toEntity() {
    return UserItem(
      id: id,
      title: title,
      subtitle: subtitle,
      price: price,
      imageCount: imageCount,
      imageUrl: imageUrl,
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

  static int _extractImageCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is List) return raw.where((e) => e != null && e.toString().trim().isNotEmpty).length;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return 0;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is List) {
            return parsed.where((e) => e != null && e.toString().trim().isNotEmpty).length;
          }
        } catch (_) {}
      }
      if (trimmed.contains(',')) {
        return trimmed.split(',').where((p) => p.trim().isNotEmpty).length;
      }
      return 1;
    }
    return 0;
  }
}
