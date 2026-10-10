import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
  ItemDetail item({required bool isOwner, List<String> imageUrls = const []}) =>
      ItemDetail(
        id: 7,
        owner: const ItemOwner(
          userId: 'owner-id',
          displayName: 'Jessica',
          imageUrl: '',
        ),
        name: 'ชุดรวมเลนส์รวม',
        imageUrls: imageUrls,
        description: 'อุปกรณ์ถ่ายภาพสำหรับงานทุกประเภท',
        category: 'กล้องและอุปกรณ์ถ่ายภาพ',
        price: 1000,
        status: 'verified',
        rentalType: 'รายวัน',
        reviews: const [],
        isOwner: isOwner,
      );

  Future<void> pumpDetail(
    WidgetTester tester, {
    required bool isOwner,
    List<String> imageUrls = const [],
  }) async {
    final repository = _MockItemDetailRepository();
    final bloc = ItemDetailBloc(
      getItem: GetItemDetailUseCase(repository),
      updateItem: UpdateItemUseCase(repository),
      initialItem: item(isOwner: isOwner, imageUrls: imageUrls),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: const ItemDetailScreen(itemId: 7),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows edit action when the signed-in user owns the item', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: true);

    expect(find.text('แก้ไขอุปกรณ์ของคุณ'), findsOneWidget);
    expect(find.text('แชท'), findsNothing);
  });

  testWidgets('shows chat action when the signed-in user is not the owner', (
    tester,
  ) async {
    await pumpDetail(tester, isOwner: false);

    expect(find.text('แชท'), findsOneWidget);
    expect(find.text('แก้ไขอุปกรณ์ของคุณ'), findsNothing);
  });

  testWidgets('asks for a contact phone before opening a rental chat', (
    tester,
  ) async {
    AuthSession.saveAccessToken('test-access-token');
    addTearDown(AuthSession.clear);
    await pumpDetail(tester, isOwner: false);

    await tester.tap(find.text('แชท'));
    await tester.pumpAndSettle();

    expect(find.text('เพิ่มเบอร์โทรศัพท์'), findsOneWidget);
    expect(find.text('กรุณาใส่เบอร์โทรศัพท์สำหรับการติดต่อ'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsOneWidget);
    expect(find.text('เพิ่มเบอร์โทร'), findsOneWidget);
  });

  testWidgets(
    'renders top floating action buttons: back, share, favorite, report flag',
    (tester) async {
      await pumpDetail(tester, isOwner: false);

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);

      // Tap favorite to toggle state
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      // Tap report flag to open bottom sheet
      await tester.tap(find.byIcon(Icons.flag_outlined));
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
}
