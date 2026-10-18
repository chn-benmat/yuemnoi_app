import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/user_item.dart';

part 'user_item_model.g.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลอุปกรณ์ของผู้ใช้จาก item_tb ในชั้น Data
@JsonSerializable(createToJson: false)
class UserItemModel {
  final int? id;
  @JsonKey(name: 'item_name', fromJson: _title)
  final String title;
  @JsonKey(readValue: _readSubtitle)
  final String subtitle;
  final double price;
  @JsonKey(readValue: _readImages, fromJson: _imageCount)
  final int imageCount;
  @JsonKey(readValue: _readImages, fromJson: _extractFirstImageUrl)
  final String? imageUrl;
  @JsonKey(fromJson: _category)
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

  factory UserItemModel.fromJson(Map<String, dynamic> json) =>
      _$UserItemModelFromJson(json);

  static String _title(Object? value) => value?.toString() ?? 'อุปกรณ์';
  static String _category(Object? value) => value?.toString() ?? 'ทั่วไป';
  static Object? _readImages(Map json, String key) => json['item_image_url'];
  static Object? _readSubtitle(Map json, String key) {
    final description = json['description']?.toString() ?? '';
    return description.isNotEmpty
        ? description
        : 'หมวดหมู่: ${_category(json['category'])}';
  }

  static int _imageCount(Object? value) {
    final count = _extractImageCount(value);
    return count > 0 ? count : 1;
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
    if (raw is List)
      return raw
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .length;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return 0;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is List) {
            return parsed
                .where((e) => e != null && e.toString().trim().isNotEmpty)
                .length;
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
