import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';

class FaqItemData {
  final String question;
  final String answer;
  bool isExpanded;

  FaqItemData({
    required this.question,
    required this.answer,
    this.isExpanded = false,
  });
}

class FaqTile extends StatelessWidget {
  final FaqItemData item;
  final VoidCallback onToggle;

  const FaqTile({super.key, required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: item.isExpanded
                ? const Color(0xFFD6BCEC)
                : const Color(0xFFE5DFEC),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: item.isExpanded,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.question,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 16,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: item.isExpanded
                                ? AppColors.primaryColor
                                : const Color(0xFF292235),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        turns: item.isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.primaryColor,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (item.isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1, color: Color(0xFFECE6F2)),
                    const SizedBox(height: 16),
                    SelectableText(
                      item.answer,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        height: 1.8,
                        color: Color(0xFF665D73),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
