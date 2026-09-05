import '../../domain/entities/user_profile.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลโปรไฟล์ผู้ใช้ระหว่าง JSON / Map กับ Entity ในชั้น Data
class UserProfileModel {
  final String userId;
  final String displayName;
  final String username;
  final String email;
  final String phone;
  final String bio;
  final String? avatarUrl;
  final double rating;
  final bool isVerified;

  const UserProfileModel({
    required this.userId,
    this.displayName = '',
    this.username = '',
    this.email = '',
    this.phone = '',
    this.bio = '',
    this.avatarUrl,
    this.rating = 0.0,
    this.isVerified = false,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      userId: json['user_id']?.toString() ?? json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ??
          json['full_name']?.toString() ??
          '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      avatarUrl: (json['user_image_url'] ?? json['avatar_url'] ?? json['picture'])?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      isVerified: json['is_verified'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'username': username,
      'email': email,
      'phone': phone,
      'bio': bio,
      'user_image_url': avatarUrl,
      'rating': rating,
      'is_verified': isVerified,
    };
  }

  UserProfile toEntity() {
    return UserProfile(
      userId: userId,
      displayName: displayName,
      username: username,
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
      email: entity.email,
      phone: entity.phone,
      bio: entity.bio,
      avatarUrl: entity.avatarUrl,
      rating: entity.rating,
      isVerified: entity.isVerified,
    );
  }
}
