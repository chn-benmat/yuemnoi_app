import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/cache/network_image_cache_key.dart';

void main() {
  test(
    'private image cache reuses rotations and separates accounts and versions',
    () {
      const url =
          'https://example.test/storage/v1/object/sign/chat_bk/room/photo.jpg';
      expect(
        networkImageCacheKey('$url?token=old', ownerId: 'alice'),
        networkImageCacheKey('$url?token=new', ownerId: 'alice'),
      );
      expect(
        networkImageCacheKey('$url?token=old', ownerId: 'alice'),
        isNot(networkImageCacheKey('$url?token=new', ownerId: 'bob')),
      );
      expect(
        networkImageCacheKey('$url?token=old&cacheNonce=1', ownerId: 'alice'),
        isNot(
          networkImageCacheKey('$url?token=new&cacheNonce=2', ownerId: 'alice'),
        ),
      );
      expect(
        networkImageCacheKey('https://example.test/photo.jpg?v=2'),
        'https://example.test/photo.jpg?v=2',
      );
    },
  );
}
