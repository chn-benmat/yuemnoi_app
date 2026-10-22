import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_stacked_image_card.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_cached_image.dart';
import 'package:frontend/features/chat/presentation/widgets/item_inquiry_bubble_card.dart';
import 'package:frontend/features/item_detail/presentation/widgets/full_screen_image_viewer.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineCacheManager extends Mock implements BaseCacheManager {
  final requestedKeys = <String>[];
  final requestedUrls = <String>[];
  bool failImages = false;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requestedKeys.add(key ?? url);
    requestedUrls.add(url);
    if (failImages) return Stream.error(StateError('expired image link'));
    // หยุดที่ cache miss เพื่อวัดการรอรูปโดยไม่เรียกเครือข่ายจริง
    return const Stream<FileResponse>.empty();
  }
}

void main() {
  late _OfflineCacheManager cacheManager;
  late ui.Image sampleImage;

  setUpAll(() async {
    CachedNetworkImageProvider.defaultCacheManager = _OfflineCacheManager();
    await initializeDateFormatting('th', null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookingConfirmationTracker.clearMemoryCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    cacheManager = _OfflineCacheManager();
    CachedNetworkImageProvider.defaultCacheManager = cacheManager;
    sampleImage = await createTestImage();
  });

  tearDown(() {
    CachedNetworkImageProvider.defaultCacheManager = _OfflineCacheManager();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    BookingConfirmationTracker.clearMemoryCache();
    sampleImage.dispose();
  });

  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SizedBox(width: 320, child: card)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> warmDisplayedImage(WidgetTester tester, Widget card) async {
    await pumpCard(tester, card);
    final imageWidget = tester.widget<Image>(find.byType(Image).first);
    final key = await imageWidget.image.obtainKey(ImageConfiguration.empty);
    await tester.pumpWidget(const SizedBox.shrink());
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    // ใส่ภาพที่ถอดรหัสแล้วด้วย key ของ widget จริง เหมือนเปิดดูสำเร็จครั้งก่อน
    imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: sampleImage.clone())),
      ),
    );
    await tester.pump();
    cacheManager.requestedKeys.clear();
  }

  ChatStackedImageCard imageCard(String url) =>
      ChatStackedImageCard(imageUrls: [url], isMine: true);

  const firstSignedUrl =
      'https://fixture.invalid/storage/v1/object/sign/chat_bk/conversation/photo.jpg?token=first';
  const refreshedSignedUrl =
      'https://fixture.invalid/storage/v1/object/sign/chat_bk/conversation/photo.jpg?token=refreshed';

  testWidgets('an expired image is requested again after URL recovery', (
    tester,
  ) async {
    cacheManager.failImages = true;
    await pumpCard(
      tester,
      ChatCachedImage(
        imageUrl: firstSignedUrl,
        refreshImageUrl: (_) async => refreshedSignedUrl,
        errorWidget: (_, _, _) => const Text('unavailable'),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(cacheManager.requestedUrls, contains(refreshedSignedUrl));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reopening an unchanged cached chat image does not wait for IO', (
    tester,
  ) async {
    await warmDisplayedImage(tester, imageCard(firstSignedUrl));
    await pumpCard(tester, imageCard(firstSignedUrl));

    expect(cacheManager.requestedKeys, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an expired fullscreen image can recover before history refreshes',
    (tester) async {
      cacheManager.failImages = true;
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenImageViewer(
            imageUrls: const [firstSignedUrl],
            refreshImageUrl: (_) async => refreshedSignedUrl,
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(cacheManager.requestedUrls, contains(refreshedSignedUrl));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a failed image reloads when realtime supplies a fresh URL', (
    tester,
  ) async {
    cacheManager.failImages = true;
    await pumpCard(tester, const ChatCachedImage(imageUrl: firstSignedUrl));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    cacheManager.requestedUrls.clear();
    await pumpCard(tester, const ChatCachedImage(imageUrl: refreshedSignedUrl));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(cacheManager.requestedUrls, contains(refreshedSignedUrl));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a queued image error cannot replace a newly selected image', (
    tester,
  ) async {
    final refreshes = <String>[];
    Future<String> refresh(String url) async {
      refreshes.add(url);
      return refreshedSignedUrl;
    }

    await pumpCard(
      tester,
      ChatCachedImage(imageUrl: firstSignedUrl, refreshImageUrl: refresh),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    image.errorWidget!(
      tester.element(find.byType(CachedNetworkImage)),
      firstSignedUrl,
      StateError('expired'),
    );
    const otherImage = 'https://fixture.invalid/another.jpg';
    await pumpCard(
      tester,
      ChatCachedImage(imageUrl: otherImage, refreshImageUrl: refresh),
    );
    await tester.pump();
    expect(refreshes, isEmpty);
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      otherImage,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reopening a cached chat image after token refresh is immediate',
    (tester) async {
      await warmDisplayedImage(tester, imageCard(firstSignedUrl));
      await pumpCard(tester, imageCard(refreshedSignedUrl));

      expect(
        cacheManager.requestedKeys,
        isEmpty,
        reason:
            'The same private storage object must reuse its loaded image '
            'when only its signed access token changes.',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('inquiry and booking share a cached identical product image', (
    tester,
  ) async {
    const imageUrl =
        'https://fixture.invalid/storage/v1/object/public/items/camera.jpg';
    final timestamp = DateTime(2030, 1, 1);
    ChatMessage message(String id) => ChatMessage(
      id: id,
      conversationId: 'cache-fixture-conversation',
      senderId: 'cache-fixture-renter',
      message: 'cache fixture',
      createdAt: timestamp,
      isMine: true,
    );

    await warmDisplayedImage(
      tester,
      ItemInquiryBubbleCard(
        message: message('inquiry'),
        inquiryData: const ItemInquiryData(
          itemName: 'Camera',
          imageUrl: imageUrl,
        ),
      ),
    );
    await pumpCard(
      tester,
      BookingRequestBubbleCard(
        message: message('booking'),
        isOwner: false,
        bookingData: BookingRequestData(
          item: const BookingItemInfo(
            id: 1,
            title: 'Camera',
            imageUrl: imageUrl,
            rating: 4.8,
            reviewCount: 2,
            hourlyRate: 100,
            dailyRate: 500,
            defaultLocation: 'Pickup point',
          ),
          startDate: timestamp,
          endDate: timestamp.add(const Duration(days: 1)),
          startTime: const TimeOfDay(hour: 10, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
          location: 'Pickup point',
        ),
      ),
    );

    expect(cacheManager.requestedKeys, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
