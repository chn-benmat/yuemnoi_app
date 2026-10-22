import 'user_item.dart';

class StorefrontIdentity {
  const StorefrontIdentity({
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.isVerified = false,
  });

  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool isVerified;
}

class StorefrontReview {
  const StorefrontReview({
    required this.itemId,
    required this.rating,
    this.reviewerName = 'ผู้ใช้',
    this.avatarUrl,
    this.description = '',
    this.createdAt,
  });

  final int itemId;
  final double rating;
  final String reviewerName;
  final String? avatarUrl;
  final String description;
  final DateTime? createdAt;
}

class ReviewSummary {
  const ReviewSummary({this.total = 0, this.count = 0});

  factory ReviewSummary.fromReviews(Iterable<StorefrontReview> reviews) {
    var total = 0.0;
    var count = 0;
    for (final review in reviews) {
      if (!review.rating.isFinite || review.rating < 1 || review.rating > 5) {
        continue;
      }
      total += review.rating;
      count++;
    }
    return ReviewSummary(total: total, count: count);
  }

  final double total;
  final int count;
  double get average => count == 0 ? 0 : total / count;
}

class StorefrontItem {
  const StorefrontItem({
    required this.item,
    required this.status,
    required this.rentalType,
    this.reviews,
  });

  final UserItem item;
  final String status;
  final String rentalType;
  final ReviewSummary? reviews;

  StorefrontItem withReviews(ReviewSummary? value) => StorefrontItem(
    item: item,
    status: status,
    rentalType: rentalType,
    reviews: value,
  );
}

class ProfileStorefront {
  const ProfileStorefront({
    required this.identity,
    required this.items,
    required this.reviews,
    this.identityUnavailable = false,
    this.reviewDetails = const [],
  });

  final StorefrontIdentity? identity;
  final List<StorefrontItem> items;
  // ค่าว่างหมายถึงโหลดไม่สำเร็จ ส่วน count เท่ากับศูนย์หมายถึงยังไม่มีรีวิวจริง
  final ReviewSummary? reviews;
  final bool identityUnavailable;
  final List<StorefrontReview> reviewDetails;
}
