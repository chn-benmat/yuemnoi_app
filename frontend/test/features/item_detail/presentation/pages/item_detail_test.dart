import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/services/favorite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/pages/item_detail.dart';
import 'package:mocktail/mocktail.dart';

class _MockItemDetailRepository extends Mock implements ItemDetailRepository {}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FavoriteService.instance.init();
  });
  ItemDetail item({
    required bool isOwner,
    List<String> imageUrls = const [],
    String description = 'อุปกรณ์ถ่ายภาพสำหรับงานทุกประเภท',
    String status = 'verified',
    bool ownerVerified = false,
    List<ItemReview> reviews = const [],
    bool longContent = false,
    bool dualPricing = false,
  }) => ItemDetail(
    id: 7,
    owner: ItemOwner(
      userId: 'owner-id',
      displayName: 'Jessica',
      imageUrl: '',
      isVerified: ownerVerified,
    ),
    name: longContent
        ? 'ชุดกล้องพร้อมเลนส์สำหรับถ่ายภาพและวิดีโอในทุกโอกาส'
        : 'ชุดรวมเลนส์รวม',
    imageUrls: imageUrls,
    description: description,
    category: 'กล้องและอุปกรณ์ถ่ายภาพ',
    price: dualPricing ? 75 : (longContent ? 1250000 : 1000),
    additionalDailyPrice: dualPricing ? 410 : null,
    status: status,
    rentalType: dualPricing ? 'รายชั่วโมง' : 'รายวัน',
    reviews: reviews,
    isOwner: isOwner,
    pickupLocation: longContent
        ? const PickupLocation(
            name: 'หน้ามหาวิทยาลัยบริเวณประตูทางเข้าฝั่งสถานีรถไฟฟ้า',
            address: 'กรุงเทพมหานคร',
            latitude: 13.75,
            longitude: 100.5,
          )
        : null,
  );

  Future<void> pumpDetail(
    WidgetTester tester, {
    required bool isOwner,
    List<String> imageUrls = const [],
    String description = 'อุปกรณ์ถ่ายภาพสำหรับงานทุกประเภท',
    String status = 'verified',
    bool ownerVerified = false,
    List<ItemReview> reviews = const [],
    bool longContent = false,
    double textScale = 1,
    bool preview = false,
    bool dualPricing = false,
  }) async {
    final repository = _MockItemDetailRepository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repository),
      updateItem: UpdateItemUseCase(repository),
      initialItem: item(
        isOwner: isOwner,
        imageUrls: imageUrls,
        description: description,
        status: status,
        ownerVerified: ownerVerified,
        longContent: longContent,
        dualPricing: dualPricing,
        reviews: reviews,
      ),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BlocProvider.value(
          value: bloc,
          child: ItemDetailScreen(itemId: 7, preview: preview),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows hourly and daily rental prices on the item detail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpDetail(tester, isOwner: false, dualPricing: true, textScale: 1.3);
    expect(find.text('ค่าเช่า / ชั่วโมง'), findsOneWidget);
    expect(find.text('฿75'), findsOneWidget);
    expect(find.text('฿410 / วัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review content stays readable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const message = 'Great condition and easy pickup. Would rent again!';
    await pumpDetail(
      tester,
      isOwner: false,
      textScale: 1.3,
      reviews: const [
        ItemReview(
          id: 1,
          reviewer: ItemOwner(
            userId: 'renter',
            displayName: 'A very long reviewer display name',
            imageUrl: '',
          ),
          rating: 4.5,
          description: message,
        ),
      ],
    );
    await tester.ensureVisible(find.text(message));
    await tester.pumpAndSettle();
    expect(find.text('4.5/5'), findsOneWidget);
    final text = tester.widget<Text>(find.text(message));
    expect(text.style?.fontStyle, isNot(FontStyle.italic));
    expect(text.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviews swipe, auto advance, cap at four and open more', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final reviews = List.generate(
      6,
      (index) => ItemReview(
        id: index,
        reviewer: ItemOwner(
          userId: 'r$index',
          displayName: 'Renter $index',
          imageUrl: '',
        ),
        rating: index == 5 ? 1 : 5,
        description: 'Review number $index',
      ),
    );
    await pumpDetail(tester, isOwner: false, reviews: reviews);
    final carousel = find.byKey(const ValueKey('review-carousel'));
    await tester.ensureVisible(carousel);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageView>(carousel).childrenDelegate.estimatedChildCount,
      4,
    );
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.drag(carousel, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);
    await tester.ensureVisible(find.text('ดูเพิ่มเติม'));
    await tester.tap(find.text('ดูเพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(find.text('รีวิวทั้งหมด'), findsOneWidget);
    final list = find.byType(ListView);
    await tester.scrollUntilVisible(
      find.text('Review number 5'),
      300,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(find.text('Review number 5'), findsOneWidget);
    await tester.tap(find.text('1 ดาว'));
    await tester.pumpAndSettle();
    expect(find.text('1 รีวิว'), findsOneWidget);
    expect(find.text('Review number 0'), findsNothing);
    expect(find.text('Review number 5'), findsOneWidget);
    await tester.tap(find.text('2 ดาว'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีรีวิวในระดับดาวนี้'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows option A management sections for the owner', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: true);

    expect(find.text('รายละเอียดอุปกรณ์'), findsOneWidget);
    expect(find.text('ดูรายละเอียด'), findsNothing);
    expect(find.text('การแสดงผล'), findsOneWidget);
    expect(find.text('แก้ไขอุปกรณ์'), findsOneWidget);
    expect(find.text('ข้อความตอบกลับอัตโนมัติ'), findsOneWidget);
    expect(find.text('ตั้งค่าการเช่า'), findsNothing);
    expect(find.text('รูปภาพ'), findsNothing);
    expect(find.text('ลบอุปกรณ์'), findsOneWidget);
    expect(find.text('แชทสอบถาม'), findsNothing);
  });

  testWidgets(
    'owner can preview the renter view without chatting with themselves',
    (tester) async {
      await pumpDetail(tester, isOwner: true, preview: true);
      expect(find.text('แชทสอบถาม'), findsOneWidget);
      expect(find.text('การแสดงผล'), findsNothing);
      expect(find.text('แก้ไขอุปกรณ์'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('แชทสอบถาม'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('owner management does not show a rental status badge', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: true, status: 'available');
    expect(find.text('เปิดให้เช่า'), findsNothing);
    expect(find.text('พร้อมให้เช่า'), findsNothing);
    expect(find.text('ดูรายละเอียด'), findsNothing);
  });

  testWidgets('shows chat action when the signed-in user is not the owner', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: false);

    expect(find.text('แชทสอบถาม'), findsOneWidget);
    expect(find.text('฿1,000'), findsOneWidget);
    expect(find.text('แก้ไขอุปกรณ์ของคุณ'), findsNothing);
    expect(find.text('การแสดงผล'), findsNothing);
    expect(find.text('ลบอุปกรณ์'), findsNothing);
  });

  for (final isOwner in [false, true]) {
    testWidgets(
      '${isOwner ? 'owner' : 'renter'} opens the pickup pin in external Google Maps',
      (tester) async {
        final launches = <MethodCall>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            launches.add(call);
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await pumpDetail(tester, isOwner: isOwner, longContent: true);

        final location = find.text(
          isOwner
              ? 'หน้ามหาวิทยาลัยบริเวณประตูทางเข้าฝั่งสถานีรถไฟฟ้า\nกรุงเทพมหานคร'
              : 'หน้ามหาวิทยาลัยบริเวณประตูทางเข้าฝั่งสถานีรถไฟฟ้า',
        );
        await tester.ensureVisible(location);
        await tester.pumpAndSettle();
        await tester.tap(location);
        await tester.pumpAndSettle();

        expect(launches, hasLength(1));
        expect(launches.single.method, 'launch');
        final arguments = launches.single.arguments as Map;
        final uri = Uri.parse(arguments['url'] as String);
        expect(uri.host, 'www.google.com');
        expect(uri.path, '/maps/search/');
        expect(uri.queryParameters['api'], '1');
        expect(uri.queryParameters['query'], '13.75,100.5');
        expect(arguments['useWebView'], isFalse);
        expect(arguments['useSafariVC'], isFalse);
        expect(
          Navigator.of(tester.element(find.byType(ItemDetailScreen))).canPop(),
          isFalse,
        );
      },
    );
  }

  testWidgets('asks for a contact phone before opening a rental chat', (
    tester,
  ) async {
    AuthSession.saveAccessToken('test-access-token');
    addTearDown(AuthSession.clear);
    await pumpDetail(tester, isOwner: false);

    await tester.tap(find.text('แชทสอบถาม'));
    await tester.pumpAndSettle();

    expect(find.text('เพิ่มเบอร์โทรศัพท์'), findsOneWidget);
    expect(find.text('กรุณาใส่เบอร์โทรศัพท์สำหรับการติดต่อ'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsOneWidget);
    expect(find.text('เพิ่มเบอร์โทร'), findsOneWidget);
  });

  testWidgets(
    'renders top floating action buttons and reports from the overflow menu',
    (tester) async {
      await pumpDetail(tester, isOwner: false);

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);

      // Tap favorite to toggle state
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // รายงานปัญหาอยู่ในเมนูเพิ่มเติม เพื่อให้ส่วนรูปสินค้าโปร่งขึ้น
      await tester.tap(find.byTooltip('เพิ่มเติม'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('รายงานปัญหา'));
      await tester.pumpAndSettle();

      expect(find.text('รายงานปัญหาอุปกรณ์นี้'), findsOneWidget);
      expect(find.text('เนื้อหาไม่เหมาะสม / หลอกลวง'), findsOneWidget);
      await tester.tap(find.text('เนื้อหาไม่เหมาะสม / หลอกลวง'));
      await tester.pumpAndSettle();
      expect(find.text('เข้าสู่ระบบเพื่อรายงานปัญหา'), findsOneWidget);
      expect(
        find.text('ส่งรายงานปัญหาให้ทีมงานตรวจสอบเรียบร้อยแล้ว'),
        findsNothing,
      );
    },
  );

  testWidgets('renders image counter badge when item has images', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      isOwner: false,
      imageUrls: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );

    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('long descriptions expand while the chat action stays fixed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final description = List.filled(
      12,
      'รายละเอียดเลนส์และอุปกรณ์ที่ให้เช่า',
    ).join('\n');
    await pumpDetail(tester, isOwner: false, description: description);
    await tester.ensureVisible(find.text('อ่านเพิ่มเติม'));
    await tester.pumpAndSettle();
    final chatPosition = tester.getCenter(find.text('แชทสอบถาม'));
    final collapsedHeight = tester.getSize(find.text(description)).height;

    await tester.tap(find.text('อ่านเพิ่มเติม'));
    await tester.pump();

    expect(
      tester.getSize(find.text(description)).height,
      greaterThan(collapsedHeight),
    );
    expect(tester.getCenter(find.text('แชทสอบถาม')), chatPosition);
    await tester.ensureVisible(find.text('ย่อรายละเอียด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ย่อรายละเอียด'));
    await tester.pump();
    expect(tester.getSize(find.text(description)).height, collapsedHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification and rental readiness follow actual item data', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: false);
    expect(find.text('พร้อมให้เช่า'), findsNothing);
    expect(find.text('ยืนยันตัวตนแล้ว'), findsNothing);

    await pumpDetail(
      tester,
      isOwner: false,
      ownerVerified: true,
      status: 'available',
    );
    expect(find.text('พร้อมให้เช่า'), findsNothing);
    expect(find.text('ยืนยันตัวตนแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 375.0, 414.0, 768.0]) {
    testWidgets('keeps rental price and chat usable at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDetail(
        tester,
        isOwner: false,
        status: 'available',
        ownerVerified: true,
        longContent: true,
        textScale: 1.3,
      );
      final chat = find.text('แชทสอบถาม');
      final chatPosition = tester.getCenter(chat);
      expect(chatPosition.dx, inExclusiveRange(0, width));
      expect(chatPosition.dy, inExclusiveRange(0, 900));
      await tester.drag(
        find.byKey(const ValueKey('item-detail-scroll')),
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(chat), chatPosition);
      expect(
        find
            .descendant(
              of: find.byKey(const ValueKey('item-chat-action-bar')),
              matching: find.text('฿1,250,000'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
