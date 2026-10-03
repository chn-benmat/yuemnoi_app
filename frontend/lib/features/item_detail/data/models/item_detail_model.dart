import '../../domain/entities/item_detail.dart';

abstract final class ItemDetailModel {
  static ItemDetail fromRecords({
    required Map<String, dynamic> item,
    required Map<String, Map<String, dynamic>> profilesByUserId,
    required List<Map<String, dynamic>> reviews,
    required String? currentUserId,
  }) {
    final id = _requiredInt(item['id'], 'item id');
    final ownerId = _string(item['user_id']);
    if (ownerId.isEmpty) throw const FormatException('Invalid item owner');

    final owner = _owner(ownerId, profilesByUserId[ownerId]);
    final mappedReviews = reviews
        .map((review) {
          final reviewerId = _string(review['user_id']);
          return ItemReview(
            id: _requiredInt(review['id'], 'review id'),
            reviewer: _owner(reviewerId, profilesByUserId[reviewerId]),
            rating: _rating(review['rating']),
            description: _string(review['description']),
          );
        })
        .toList(growable: false);

    return ItemDetail(
      id: id,
      owner: owner,
      name: _fallbackString(item['item_name'], 'อุปกรณ์ให้เช่า'),
      imageUrls: _imageUrls(item['item_image_url']),
      description: _string(item['description']),
      category: _fallbackString(item['category'], 'อุปกรณ์'),
      price: _optionalInt(item['price']) ?? 0,
      status: _string(item['status']),
      rentalType: _normalizeRentalType(item['type']),
      reviews: mappedReviews,
      isOwner: currentUserId != null && currentUserId == ownerId,
    );
  }

  static ItemDetail fromApiResponse({
    required Map<String, dynamic> item,
    required String? currentUserId,
  }) {
    final id = _requiredInt(item['id'], 'item id');
    final ownerId = _string(item['user_id']);
    if (ownerId.isEmpty) throw const FormatException('Invalid item owner');

    final owner = ItemOwner(
      userId: ownerId,
      displayName: _fallbackString(item['owner_name'], 'ผู้ใช้งาน Yuemnoi'),
      imageUrl: _string(item['owner_avatar_url']),
    );

    return ItemDetail(
      id: id,
      owner: owner,
      name: _fallbackString(item['item_name'], 'อุปกรณ์ให้เช่า'),
      imageUrls: _imageUrls(item['item_image_url']),
      description: _string(item['description']),
      category: _fallbackString(item['category'], 'อุปกรณ์'),
      price: _optionalInt(item['price']) ?? 0,
      status: _string(item['status']),
      rentalType: _normalizeRentalType(item['type']),
      reviews: const [],
      isOwner: currentUserId != null && currentUserId == ownerId,
    );
  }

  static ItemOwner _owner(String userId, Map<String, dynamic>? profile) {
    final displayName = _string(profile?['display_name']);
    final email = _string(profile?['email']);
    final emailName = email.contains('@') ? email.split('@').first : email;
    final name = displayName.isNotEmpty
        ? displayName
        : (emailName.isNotEmpty ? emailName : 'ผู้ใช้งาน Yuemnoi');
    return ItemOwner(
      userId: userId,
      displayName: name,
      imageUrl: _string(profile?['user_image_url']),
    );
  }

  static List<String> _imageUrls(Object? value) {
    if (value is! List) return const [];
    return value
        .map(_string)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  static double _rating(Object? value) {
    final rating = value is num ? value.toDouble() : double.tryParse('$value');
    return (rating ?? 0).clamp(0, 5).toDouble();
  }

  static int _requiredInt(Object? value, String field) {
    final parsed = _optionalInt(value);
    if (parsed == null) throw FormatException('Invalid $field');
    return parsed;
  }

  static int? _optionalInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  static String _fallbackString(Object? value, String fallback) {
    final parsed = _string(value);
    return parsed.isEmpty ? fallback : parsed;
  }

  static String _normalizeRentalType(Object? value) {
    final str = _string(value).toLowerCase();
    if (str == 'hour' || str == 'hourly' || str == 'รายชั่วโมง') {
      return 'รายชั่วโมง';
    }
    return 'รายวัน';
  }

  static String _string(Object? value) =>
      value is String ? value.trim() : value?.toString().trim() ?? '';
}
