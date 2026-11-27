import 'package:flutter/widgets.dart';

class ProductCardGrid extends StatelessWidget {
  const ProductCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : _sliver = true;

  const ProductCardGrid.box({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  }) : _sliver = false;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool _sliver;

  @override
  Widget build(BuildContext context) {
    final rowCount = (itemCount + 1) ~/ 2;
    const spacing = SizedBox(height: 10);
    if (!_sliver) {
      return Column(
        children: [
          for (var index = 0; index < rowCount; index++) ...[
            if (index > 0) spacing,
            _buildRow(context, index),
          ],
        ],
      );
    }
    return SliverList.separated(
      itemCount: rowCount,
      separatorBuilder: (_, _) => spacing,
      itemBuilder: _buildRow,
    );
  }

  Widget _buildRow(BuildContext context, int rowIndex) {
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
  }
}
