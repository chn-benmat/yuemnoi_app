import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/services/favorite_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../bloc/favorite_cubit.dart';
import '../../bloc/favorite_state.dart';
import '../../widgets/items/favorite_widgets.dart';

class FavoriteScreen extends StatefulWidget {
  const FavoriteScreen({super.key});

  @override
  State<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends State<FavoriteScreen> {
  late final FavoriteCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FavoriteCubit();
    _cubit.loadFavorites();
    FavoriteService.instance.favoritesNotifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    FavoriteService.instance.favoritesNotifier.removeListener(
      _onFavoritesChanged,
    );
    _cubit.close();
    super.dispose();
  }

  void _onFavoritesChanged() {
    _cubit.loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F9),
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          leading: const BackButton(),
          title: const Text(
            'อุปกรณ์เช่าที่ถูกใจ',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: BlocBuilder<FavoriteCubit, FavoriteState>(
          builder: (context, state) {
            if (state is FavoriteLoading || state is FavoriteInitial) {
              return const FavoriteLoadingSkeleton();
            }

            final items = state is FavoriteLoaded ? state.items : [];

            if (items.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: () async => _cubit.loadFavorites(),
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final cardData = FavoriteItemData.fromEntity(item);
                  return FavoriteItemCard(
                    item: cardData,
                    onRemoveFavorite: () async {
                      await FavoriteService.instance.toggleFavorite(item.id);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                color: AppColors.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ยังไม่มีอุปกรณ์เช่าที่ถูกใจ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'กดไอคอนหัวใจที่อุปกรณ์ที่คุณสนใจเพื่อบันทึกไว้ดูภายหลังในหน้านี้',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.hintTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'ค้นหาอุปกรณ์เช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
