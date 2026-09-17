// คำอธิบาย: Entity สำหรับเก็บข้อมูลโปรไฟล์ผู้ใช้ในชั้น Domain
class UserProfile {
  final String userId;
  final String displayName;
  final String username;
  final String email;
  final String phone;
  final String bio;
  final String? avatarUrl;
  final double rating;
  final bool isVerified;

  const UserProfile({
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

  UserProfile copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? email,
    String? phone,
    String? bio,
    String? avatarUrl,
    double? rating,
    bool? isVerified,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      rating: rating ?? this.rating,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
