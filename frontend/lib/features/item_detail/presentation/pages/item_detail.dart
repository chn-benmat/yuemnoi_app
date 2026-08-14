import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../chat/domain/entities/chat_conversation.dart';
import '../../domain/entities/item_detail.dart';
import '../bloc/item_detail_bloc.dart';
import '../bloc/item_detail_event.dart';
import '../bloc/item_detail_state.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final int itemId;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _isFavorite = false;

  Future<void> _openEdit(ItemDetail item) async {
    final updated = await AppRoutes.openEditRentalItem(context, item: item);
    if (updated == true && mounted) {
      context.read<ItemDetailBloc>().add(ItemDetailRequested(widget.itemId));
    }
  }

  Future<void> _openChat(ItemDetail item) {
    final owner = item.owner;
    return AppRoutes.openConversation(
      context,
      conversation: ChatConversation(
        id: 'item-${item.id}-${owner.userId}',
        name: owner.displayName,
        role: ChatParticipantRole.renter,
        avatarAsset: owner.imageUrl.isEmpty
            ? 'assets/images/yuemnoi.png'
            : owner.imageUrl,
        preview: 'สนใจเช่า ${item.name}',
        timeLabel: 'ตอนนี้',
        isOnline: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemDetailBloc, ItemDetailState>(
      builder: (context, state) {
        final item = state.item;
        return Scaffold(
          backgroundColor: Colors.white,
          bottomNavigationBar: item == null
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
                    child: AppPrimaryButton(
                      text: item.isOwner
                          ? 'แก้ไขอุปกรณ์ของคุณ'
                          : 'คุยกับผู้ปล่อยเช่า',
                      onPressed: () =>
                          item.isOwner ? _openEdit(item) : _openChat(item),
                    ),
                  ),
                ),
          body: Column(
            children: [
              _DetailTopBar(
                isFavorite: _isFavorite,
                onFavorite: () => setState(() => _isFavorite = !_isFavorite),
                onShare: () {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('คัดลอกลิงก์อุปกรณ์แล้ว')),
                    );
                },
              ),
              Expanded(child: _body(state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(ItemDetailState state) {
    final item = state.item;
    if (item == null &&
        (state.status == ItemDetailStatus.loading ||
            state.status == ItemDetailStatus.initial)) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }
    if (item == null) {
      return _LoadError(
        message: state.errorMessage ?? 'โหลดรายละเอียดอุปกรณ์ไม่สำเร็จ',
        onRetry: () => context.read<ItemDetailBloc>().add(
          ItemDetailRequested(widget.itemId),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primaryColor,
      onRefresh: () async {
        context.read<ItemDetailBloc>().add(ItemDetailRequested(widget.itemId));
        await context.read<ItemDetailBloc>().stream.firstWhere(
          (next) => next.status != ItemDetailStatus.loading,
        );
      },
      child: CustomScrollView(
        key: const ValueKey('item-detail-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _ImageGallery(imageUrls: item.imageUrls),
                Transform.translate(
                  offset: const Offset(0, -38),
                  child: _DetailContent(item: item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
  });

  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primaryColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                tooltip: 'ย้อนกลับ',
                onPressed: () => AppRoutes.pop(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: isFavorite
                    ? 'นำออกจากรายการโปรด'
                    : 'เพิ่มในรายการโปรด',
                onPressed: onFavorite,
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              IconButton(
                tooltip: 'แชร์',
                onPressed: onShare,
                icon: const Icon(
                  Icons.share_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageGallery extends StatefulWidget {
  const _ImageGallery({required this.imageUrls});

  final List<String> imageUrls;

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    return SizedBox(
      height: 500,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (urls.isEmpty)
            const ColoredBox(
              color: Color(0xFFE9E9EC),
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Color(0xFF9A9A9F),
                size: 58,
              ),
            )
          else
            PageView.builder(
              key: const ValueKey('item-image-gallery'),
              itemCount: urls.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                placeholder: (context, url) => const ColoredBox(
                  color: Color(0xFFE9E9EC),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => const ColoredBox(
                  color: Color(0xFFE9E9EC),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9A9A9F),
                    size: 58,
                  ),
                ),
              ),
            ),
          if (urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  urls.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: index == _page ? 28 : 8,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.item});

  final ItemDetail item;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 600),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(42)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 38, 28, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Color(0xFF2D2D30),
                            fontSize: 27,
                            height: 1.16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${NumberFormat.decimalPattern().format(item.price)} ฿',
                        style: const TextStyle(
                          color: Color(0xFF2D2D30),
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'ต่อ${item.unitLabel}',
                        style: const TextStyle(
                          color: Color(0xFF6F6F74),
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 48),
              _OwnerCard(item: item),
              const SizedBox(height: 40),
              const _SectionTitle('คำอธิบาย'),
              const SizedBox(height: 14),
              Text(
                item.description.isEmpty
                    ? 'ไม่มีคำอธิบายเพิ่มเติม'
                    : item.description,
                style: const TextStyle(
                  color: Color(0xFF5D5D62),
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
              const SizedBox(height: 40),
              const _SectionTitle('รีวิวล่าสุด'),
              const SizedBox(height: 18),
              if (item.reviews.isEmpty)
                const _EmptyReviews()
              else
                for (final review in item.reviews) ...[
                  _ReviewCard(review: review),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.item});

  final ItemDetail item;

  @override
  Widget build(BuildContext context) {
    final owner = item.owner;
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          _Avatar(imageUrl: owner.imageUrl, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  owner.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2D2D30),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'ผู้ปล่อยเช่า',
                  style: TextStyle(
                    color: Color(0xFF6B6B70),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (item.reviews.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: AppColors.primaryColor,
                    size: 19,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.averageRating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final ItemReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.reviewer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF343439),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Stars(rating: review.rating),
            ],
          ),
          if (review.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${review.description}”',
              style: const TextStyle(
                color: Color(0xFF68686D),
                fontSize: 14,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          index < rating.round()
              ? Icons.star_rounded
              : Icons.star_border_rounded,
          color: AppColors.primaryColor,
          size: 18,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.size});

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDDB4FA), width: 2),
      ),
      child: ClipOval(
        child: imageUrl.isEmpty
            ? Image.asset('assets/images/yuemnoi.png', fit: BoxFit.cover)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Image.asset('assets/images/yuemnoi.png', fit: BoxFit.cover),
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF5B5B60),
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        children: [
          Icon(Icons.rate_review_outlined, color: Color(0xFF929297), size: 30),
          SizedBox(height: 8),
          Text(
            'ยังไม่มีรีวิวสำหรับอุปกรณ์นี้',
            style: TextStyle(color: Color(0xFF77777C), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}
