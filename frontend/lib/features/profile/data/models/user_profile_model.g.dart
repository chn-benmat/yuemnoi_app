// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserProfileModel _$UserProfileModelFromJson(
  Map<String, dynamic> json,
) => UserProfileModel(
  userId: UserProfileModel._string(
    UserProfileModel._readUserId(json, 'user_id'),
  ),
  displayName: UserProfileModel._readDisplayName(json, 'display_name') == null
      ? ''
      : UserProfileModel._string(
          UserProfileModel._readDisplayName(json, 'display_name'),
        ),
  username: json['username'] == null
      ? ''
      : UserProfileModel._string(json['username']),
  email: json['email'] == null ? '' : UserProfileModel._string(json['email']),
  phone: json['phone'] == null ? '' : UserProfileModel._string(json['phone']),
  bio: json['bio'] == null ? '' : UserProfileModel._string(json['bio']),
  avatarUrl: UserProfileModel._nullableString(
    UserProfileModel._readAvatar(json, 'user_image_url'),
  ),
  rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
  isVerified: json['is_verified'] == null
      ? false
      : UserProfileModel._isTrue(json['is_verified']),
);

Map<String, dynamic> _$UserProfileModelToJson(UserProfileModel instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'display_name': instance.displayName,
      'username': instance.username,
      'email': instance.email,
      'phone': instance.phone,
      'bio': instance.bio,
      'user_image_url': instance.avatarUrl,
      'rating': instance.rating,
      'is_verified': instance.isVerified,
    };
