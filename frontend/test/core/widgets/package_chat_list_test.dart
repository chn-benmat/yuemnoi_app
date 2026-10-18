import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/package_chat_list.dart';

void main() {
  testWidgets('removing and reordering entries never renders an old index', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Future<void> show(List<String> ids) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PackageChatList(
              scrollController: scroll,
              entries: [
                for (final id in ids)
                  PackageChatEntry(id: id, authorId: 'user'),
              ],
              itemBuilder: (_, index) =>
                  SizedBox(height: 80, child: Text(ids[index])),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(['first', 'second', 'third']);
    await show(['third', 'first']);
    expect(find.text('third'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    await show(['first']);
    expect(find.text('first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
