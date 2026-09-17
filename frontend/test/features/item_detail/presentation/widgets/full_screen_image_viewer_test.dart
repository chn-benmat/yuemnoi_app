import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/presentation/widgets/full_screen_image_viewer.dart';

void main() {
  testWidgets('FullScreenImageViewer renders empty state when no images', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullScreenImageViewer(imageUrls: []),
      ),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('FullScreenImageViewer renders images and counter badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullScreenImageViewer(
          imageUrls: [
            'https://example.com/item1.jpg',
            'https://example.com/item2.jpg',
            'https://example.com/item3.jpg',
          ],
          initialIndex: 1,
        ),
      ),
    );

    expect(find.text('2/3'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Tap close button pops viewer
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });
}
