import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/profile_widgets.dart';

void main() {
  testWidgets(
    'ProfileQuickActionsRow renders image assets for all 5 quick actions',
    (tester) async {
      final items = [
        const ProfileQuickActionData(
          icon: Icons.inventory_2_outlined,
          imageAsset: 'assets/icons/camera.png',
          label: 'อุปกรณ์ของฉัน',
        ),
        const ProfileQuickActionData(
          icon: Icons.monetization_on_outlined,
          imageAsset: 'assets/icons/audio.png',
          label: 'รายได้',
        ),
        const ProfileQuickActionData(
          icon: Icons.local_shipping_outlined,
          imageAsset: 'assets/icons/computer.png',
          label: 'สถานะการเช่า',
        ),
        const ProfileQuickActionData(
          icon: Icons.favorite_border_rounded,
          imageAsset: 'assets/icons/guitar.png',
          label: 'ถูกใจ',
        ),
        const ProfileQuickActionData(
          icon: Icons.calendar_today_outlined,
          imageAsset: 'assets/icons/drill.png',
          label: 'ประวัติการเช่า',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileQuickActionsRow(items: items)),
        ),
      );
      await tester.pump();

      expect(find.text('อุปกรณ์ของฉัน'), findsOneWidget);
      expect(find.text('รายได้'), findsOneWidget);
      expect(find.text('สถานะการเช่า'), findsOneWidget);
      expect(find.text('ถูกใจ'), findsOneWidget);
      expect(find.text('ประวัติการเช่า'), findsOneWidget);

      final imageWidgets = tester
          .widgetList<Image>(find.byType(Image))
          .toList();
      expect(imageWidgets.length, 5);

      expect(
        (imageWidgets[0].image as AssetImage).assetName,
        'assets/icons/camera.png',
      );
      expect(
        (imageWidgets[1].image as AssetImage).assetName,
        'assets/icons/audio.png',
      );
      expect(
        (imageWidgets[2].image as AssetImage).assetName,
        'assets/icons/computer.png',
      );
      expect(
        (imageWidgets[3].image as AssetImage).assetName,
        'assets/icons/guitar.png',
      );
      expect(
        (imageWidgets[4].image as AssetImage).assetName,
        'assets/icons/drill.png',
      );
    },
  );
}
