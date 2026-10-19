import 'package:equatable/equatable.dart';

/// เอนทิตีแทนหมวดหมู่ของอุปกรณ์ในหน้า Home Feed
class FeedCategory extends Equatable {
  const FeedCategory({required this.id, required this.name, this.iconName});

  /// รหัสหมวดหมู่ (เช่น 'all', 'phone', 'camera', 'laptop', 'gaming', 'camping', 'audio')
  final String id;

  /// ชื่อภาษาไทยที่แสดงบนหน้าจอ
  final String name;

  /// ชื่อไอคอนอ้างอิง (ถ้ามี)
  final String? iconName;

  @override
  List<Object?> get props => [id, name, iconName];
}
