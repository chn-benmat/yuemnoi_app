import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/models/user_profile_model.dart';
import 'package:frontend/features/profile/domain/entities/user_profile.dart';

void main() {
  group('UserProfileModel', () {
    test('keeps legacy aliases and the canonical output schema', () {
      final model = UserProfileModel.fromJson({
        'id': 42,
        'full_name': 'Legacy Name',
        'avatar_url': 123,
        'phone': 812345678,
        'is_verified': 'true',
      });

      expect(model.toJson(), {
        'user_id': '42',
        'display_name': 'Legacy Name',
        'username': '',
        'email': '',
        'phone': '812345678',
        'bio': '',
        'user_image_url': '123',
        'rating': 0.0,
        'is_verified': false,
      });
      final preferred = UserProfileModel.fromJson({
        'user_id': '',
        'id': 'fallback',
        'display_name': '',
        'full_name': 'fallback',
        'user_image_url': '',
        'picture': 'fallback',
      });
      expect(preferred.userId, '');
      expect(preferred.displayName, '');
      expect(preferred.avatarUrl, '');
    });

    test('fromJson converts map correctly to UserProfileModel', () {
      final json = {
        'user_id': 'u123',
        'display_name': 'Somchai Test',
        'username': 'somchai',
        'email': 'somchai@test.com',
        'phone': '0812345678',
        'bio': 'Test bio',
        'user_image_url': 'https://example.com/pic.jpg',
        'rating': 4.8,
        'is_verified': true,
      };

      final model = UserProfileModel.fromJson(json);

      expect(model.userId, 'u123');
      expect(model.displayName, 'Somchai Test');
      expect(model.username, 'somchai');
      expect(model.email, 'somchai@test.com');
      expect(model.phone, '0812345678');
      expect(model.bio, 'Test bio');
      expect(model.avatarUrl, 'https://example.com/pic.jpg');
      expect(model.rating, 4.8);
      expect(model.isVerified, true);
    });

    test('toEntity converts correctly to UserProfile entity', () {
      const model = UserProfileModel(
        userId: 'u123',
        displayName: 'Somchai Test',
        username: 'somchai',
        email: 'somchai@test.com',
        phone: '0812345678',
        bio: 'Test bio',
        avatarUrl: 'https://example.com/pic.jpg',
        rating: 4.8,
        isVerified: true,
      );

      final entity = model.toEntity();

      expect(entity, isA<UserProfile>());
      expect(entity.userId, 'u123');
      expect(entity.displayName, 'Somchai Test');
      expect(entity.username, 'somchai');
      expect(entity.phone, '0812345678');
    });

    test('fromEntity converts correctly from UserProfile entity', () {
      const entity = UserProfile(
        userId: 'u999',
        displayName: 'Test Entity',
        username: 'testentity',
        email: 'test@example.com',
        phone: '0899999999',
        bio: 'Entity bio',
        avatarUrl: null,
        rating: 5.0,
        isVerified: false,
      );

      final model = UserProfileModel.fromEntity(entity);

      expect(model.userId, 'u999');
      expect(model.displayName, 'Test Entity');
      expect(model.username, 'testentity');
      expect(model.avatarUrl, isNull);
    });
  });
}
