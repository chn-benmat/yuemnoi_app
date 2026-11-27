import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/user_profile.dart';

part 'user_profile_model.g.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลโปรไฟล์ผู้ใช้ระหว่าง JSON / Map กับ Entity ในชั้น Data
@JsonSerializable(fieldRename: FieldRename.snake)
class UserProfileModel {
  @JsonKey(readValue: _readUserId, fromJson: _string)
  final String userId;
  @JsonKey(readValue: _readDisplayName, fromJson: _string)
  final String displayName;
  @JsonKey(fromJson: _string)
  final String username;
  @JsonKey(includeIfNull: false)
  final DateTime? usernameChangedAt;
  @JsonKey(fromJson: _string)
  final String email;
  @JsonKey(fromJson: _string)
  final String phone;
  @JsonKey(fromJson: _string)
  final String bio;
  @JsonKey(
    name: 'user_image_url',
    readValue: _readAvatar,
    fromJson: _nullableString,
  )
  final String? avatarUrl;
  final double rating;
  @JsonKey(fromJson: _isTrue)
  final bool isVerified;

  const UserProfileModel({
    required this.userId,
    this.displayName = '',
    this.username = '',
    this.usernameChangedAt,
    this.email = '',
    this.phone = '',
    this.bio = '',
    this.avatarUrl,
    this.rating = 0.0,
    this.isVerified = false,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) =>
      _$UserProfileModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserProfileModelToJson(this);

  static Object? _readUserId(Map json, String key) => json[key] ?? json['id'];
  static Object? _readDisplayName(Map json, String key) =>
      json[key] ?? json['full_name'];
  static Object? _readAvatar(Map json, String key) =>
      json[key] ?? json['avatar_url'] ?? json['picture'];
  static String _string(Object? value) => value?.toString() ?? '';
  static String? _nullableString(Object? value) => value?.toString();
  static bool _isTrue(Object? value) => value == true;

  UserProfile toEntity() {
    return UserProfile(
      userId: userId,
      displayName: displayName,
      username: username,
      usernameChangedAt: usernameChangedAt,
      email: email,
      phone: phone,
      bio: bio,
      avatarUrl: avatarUrl,
      rating: rating,
      isVerified: isVerified,
    );
  }

  factory UserProfileModel.fromEntity(UserProfile entity) {
    return UserProfileModel(
      userId: entity.userId,
      displayName: entity.displayName,
      username: entity.username,
      usernameChangedAt: entity.usernameChangedAt,
      email: entity.email,
      phone: entity.phone,
      bio: entity.bio,
      avatarUrl: entity.avatarUrl,
      rating: entity.rating,
      isVerified: entity.isVerified,
    );
  }
}
