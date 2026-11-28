import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/skeleton_layout_cache.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_skeleton_loading_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('remembers the last layout and its count', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = SkeletonLayoutCache.instance;
    await cache.init();

    expect(cache.count('unit.empty', fallback: 6), 6);
    cache.write('unit.notifications', ['u', 'r', 'r']);
    expect(cache.read('unit.notifications'), ['u', 'r', 'r']);
    cache.writeCount('unit.favorites', 20);
    expect(cache.count('unit.favorites', fallback: 6), 8);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('skeleton_layout.unit.notifications'), [
      'u',
      'r',
      'r',
    ]);
  });

  testWidgets('chat skeleton replays a measured booking card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatSkeletonLoadingView(layout: ['o|c|560|1|0|200']),
        ),
      ),
    );
    final list = find.byKey(const ValueKey('chat-detail-loading-skeleton'));
    final rows = find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 560,
      ),
    );
    expect(rows, findsOneWidget);
    // การ์ดเดียวต้องมีพื้นขาวกับขอบ และไม่มีบับเบิลข้อความอื่นปน
    expect(
      find.descendant(
        of: list,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border != null,
        ),
      ),
      findsOneWidget,
    );
  });
}
