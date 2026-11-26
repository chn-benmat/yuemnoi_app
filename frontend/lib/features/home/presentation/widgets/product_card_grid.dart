import 'package:flutter/widgets.dart';

class ProductCardGrid extends StatelessWidget {
  const ProductCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      itemCount: (itemCount + 1) ~/ 2,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, rowIndex) {
        final firstIndex = rowIndex * 2;
        final secondIndex = firstIndex + 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: itemBuilder(context, firstIndex)),
            const SizedBox(width: 10),
            Expanded(
              child: secondIndex < itemCount
                  ? itemBuilder(context, secondIndex)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
