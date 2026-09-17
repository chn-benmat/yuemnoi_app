import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/auth_guard.dart';
import '../../../../core/navigation/item_deep_link.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../chat/domain/entities/item_inquiry_data.dart';
import '../../../../core/utils/phone_formatter.dart';
import '../../../../core/services/favorite_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/presentation/pages/profile/user_profile_view_screen.dart';
import '../../domain/entities/item_detail.dart';
import '../bloc/item_detail_bloc.dart';
import '../bloc/item_detail_event.dart';
import '../bloc/item_detail_state.dart';
import '../widgets/full_screen_image_viewer.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final int itemId;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _isFavorite = false;
  bool _isChatLoading = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = FavoriteService.instance.isItemFavorite(widget.itemId);
  }

  Future<void> _handleFavoriteToggle() async {
    final isFav =
        await FavoriteService.instance.toggleFavorite(widget.itemId);
    if (!mounted) return;
    setState(() => _isFavorite = isFav);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isFav ? 'เพิ่มในรายการถูกใจแล้ว' : 'นำออกจากรายการถูกใจแล้ว',
            style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  Future<void> _openEdit(ItemDetail item) async {
    final updated = await AppRoutes.openEditRentalItem(context, item: item);
    if (updated == true && mounted) {
      context.read<ItemDetailBloc>().add(ItemDetailRequested(widget.itemId));
    }
  }

  bool _hasCurrentUserPhone() {
    if (!SupabaseConfig.isInitialized) return false;

    final user = SupabaseConfig.client.auth.currentUser;
    final rawPhone =
        user?.userMetadata?['phone']?.toString() ?? user?.phone ?? '';
    return PhoneFormatter.isValidPhone(rawPhone);
  }

  Future<void> _showMissingPhoneDialog() async {
    final shouldAddPhone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'เพิ่มเบอร์โทรศัพท์',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('กรุณาใส่เบอร์โทรศัพท์สำหรับการติดต่อ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            child: const Text('เพิ่มเบอร์โทร'),
          ),
        ],
      ),
    );

    if (shouldAddPhone == true && mounted) {
      await AppRoutes.openEditContact(context);
    }
  }

  Future<void> _openChat(ItemDetail item) async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อใช้งานแชท',
      message: 'กรุณาเข้าสู่ระบบก่อนเริ่มการสนทนากับผู้ปล่อยเช่าอุปกรณ์',
    );
    if (!authed || !mounted) {
      return;
    }

    if (item.isOwner) return;

    if (!_hasCurrentUserPhone()) {
      await _showMissingPhoneDialog();
      return;
    }

    setState(() => _isChatLoading = true);
    try {
      final repository = ChatRepositoryImpl();
      final conversation = await repository.getOrCreateConversation(
        itemId: item.id,
        ownerId: item.owner.userId,
      );

      final firstImageUrl = item.imageUrls.isNotEmpty
          ? item.imageUrls.first
          : '';
      final inquiryData = ItemInquiryData(
        itemId: item.id,
        itemName: item.name,
        price: item.price.toDouble(),
        unitLabel: item.unitLabel,
        imageUrl: firstImageUrl,
      );

      // ส่งข้อความแสดงความสนใจเช่าอุปกรณ์เข้าแชทโดยอัตโนมัติเมื่อกดแชทจากหน้ารายละเอียดอุปกรณ์
      final chatDataSource = ChatRemoteDataSource();
      try {
        await chatDataSource.sendMessage(
          conversationId: conversation.id,
          message: inquiryData.toChatMessagePayload(),
          imageUrl: firstImageUrl.isNotEmpty ? firstImageUrl : null,
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _isChatLoading = false);
        await AppRoutes.openConversation(context, conversation: conversation);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isChatLoading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _handleShare(ItemDetail? item) async {
    if (item == null) return;

    final description = item.description.trim();
    final price = NumberFormat('#,##0.##').format(item.price);
    final shareText = <String>[
      'ลองดู ${item.name} บน Yuemnoi',
      if (description.isNotEmpty) description,
      'ราคา ฿$price/${item.unitLabel}',
      ItemDeepLink.build(item.id).toString(),
    ].join('\n');

    final renderObject = context.findRenderObject();
    final sharePositionOrigin = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;

    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        title: 'แชร์ ${item.name}',
        subject: item.name,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  void _openReportOptions(ItemDetail item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: Color(0xFFEF4444),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'รายงานปัญหาอุปกรณ์นี้',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'โปรดเลือกเหตุผลที่คุณต้องการรายงาน',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFEF4444),
                  ),
                  title: const Text(
                    'เนื้อหาไม่เหมาะสม / หลอกลวง',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportSuccess();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.price_change_outlined,
                    color: Color(0xFFF59E0B),
                  ),
                  title: const Text(
                    'ราคาหรือข้อมูลอุปกรณ์ไม่ถูกต้อง',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportSuccess();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.block_rounded,
                    color: Color(0xFF64748B),
                  ),
                  title: const Text(
                    'สินค้าต้องห้ามหรือผิดกฎหมาย',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportSuccess();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.more_horiz_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  title: const Text(
                    'เหตุผลอื่นๆ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportSuccess();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReportSuccess() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('ส่งรายงานปัญหาให้ทีมงานตรวจสอบเรียบร้อยแล้ว'),
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
                      text: item.isOwner ? 'แก้ไขอุปกรณ์ของคุณ' : 'แชท',
                      isLoading: _isChatLoading,
                      onPressed: () =>
                          item.isOwner ? _openEdit(item) : _openChat(item),
                    ),
                  ),
                ),
          body: Stack(
            children: [
              _body(state),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _DetailFloatingTopBar(
                  isFavorite: _isFavorite,
                  onFavorite: _handleFavoriteToggle,
                  onShare: () => _handleShare(item),
                  onReport: () {
                    if (item != null) {
                      _openReportOptions(item);
                    }
                  },
                ),
              ),
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
      return const _ItemDetailLoadingView();
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
                  offset: const Offset(0, -32),
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

class _ItemDetailLoadingView extends StatelessWidget {
  const _ItemDetailLoadingView();

  @override
  Widget build(BuildContext context) {
    final galleryHeight = MediaQuery.sizeOf(context).width.clamp(360.0, 420.0);

    return SkeletonShimmer(
      key: const ValueKey('item-detail-skeleton'),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SkeletonBox(height: galleryHeight, borderRadius: 0),
            Transform.translate(
              offset: const Offset(0, -32),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 600),
                padding: const EdgeInsets.fromLTRB(24, 38, 24, 32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 240, height: 24, borderRadius: 12),
                    SizedBox(height: 12),
                    SkeletonBox(width: 150, height: 16, borderRadius: 8),
                    SizedBox(height: 22),
                    SkeletonBox(width: 130, height: 30, borderRadius: 15),
                    SizedBox(height: 42),
                    _OwnerCardSkeleton(),
                    SizedBox(height: 40),
                    SkeletonBox(width: 86, height: 15, borderRadius: 8),
                    SizedBox(height: 16),
                    SkeletonBox(
                      width: double.infinity,
                      height: 14,
                      borderRadius: 7,
                    ),
                    SizedBox(height: 10),
                    SkeletonBox(
                      width: double.infinity,
                      height: 14,
                      borderRadius: 7,
                    ),
                    SizedBox(height: 10),
                    SkeletonBox(width: 210, height: 14, borderRadius: 7),
                    SizedBox(height: 40),
                    SkeletonBox(width: 92, height: 15, borderRadius: 8),
                    SizedBox(height: 18),
                    SkeletonBox(
                      width: double.infinity,
                      height: 104,
                      borderRadius: 28,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerCardSkeleton extends StatelessWidget {
  const _OwnerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFE3E5E8),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        children: [
          SkeletonBox(height: 64, width: 64, shape: BoxShape.circle),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 150, height: 16, borderRadius: 8),
                SizedBox(height: 9),
                SkeletonBox(width: 82, height: 12, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailFloatingTopBar extends StatelessWidget {
  const _DetailFloatingTopBar({
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onReport,
  });

  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _CircleActionButton(
              tooltip: 'ย้อนกลับ',
              icon: Icons.arrow_back_rounded,
              onPressed: () => AppRoutes.pop(context),
            ),
            const Spacer(),
            _CircleActionButton(
              tooltip: 'แชร์',
              icon: Icons.share_outlined,
              iconSize: 20,
              onPressed: onShare,
            ),
            const SizedBox(width: 8),
            _CircleActionButton(
              tooltip: isFavorite ? 'นำออกจากรายการโปรด' : 'เพิ่มในรายการโปรด',
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              iconColor: isFavorite ? const Color(0xFFFF3B5F) : Colors.white,
              onPressed: onFavorite,
            ),
            const SizedBox(width: 8),
            _CircleActionButton(
              tooltip: 'รายงานปัญหา',
              icon: Icons.flag_outlined,
              iconSize: 20,
              onPressed: onReport,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: iconSize,
        tooltip: tooltip,
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final galleryHeight = screenWidth.clamp(360.0, 420.0);

    return Container(
      height: galleryHeight,
      color: const Color(0xFFF3F4F6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (urls.isEmpty)
            const ColoredBox(
              color: Color(0xFFE9E9EC),
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Color(0xFF9A9A9F),
                  size: 58,
                ),
              ),
            )
          else
            PageView.builder(
              key: const ValueKey('item-image-gallery'),
              itemCount: urls.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Blurred background of the same image to eliminate empty side bars
                    Transform.scale(
                      scale: 1.15,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: CachedNetworkImage(
                          imageUrl: urls[index],
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              const ColoredBox(color: Color(0xFF232428)),
                        ),
                      ),
                    ),
                    // Subtle overlay for pleasant contrast
                    Container(color: Colors.black.withValues(alpha: 0.16)),
                    // Crisp foreground uncropped image
                    GestureDetector(
                      onTap: () => FullScreenImageViewer.open(
                        context,
                        imageUrls: urls,
                        initialIndex: index,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: urls[index],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const SkeletonShimmer(
                          child: ColoredBox(color: Color(0xFFE3E5E8)),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 58,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom right image counter badge (only when multiple images e.g. 2/3)
          if (urls.length > 1)
            Positioned(
              right: 18,
              bottom: 48,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${_page + 1}/${urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 18),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppRoutes.openUserProfile(
          context,
          args: UserProfileViewArgs(
            userId: owner.userId,
            displayName: owner.displayName,
            avatarUrl: owner.imageUrl,
            rating: item.averageRating,
            isVerified: true,
            bio: 'สนใจกล้องตัวไหนโปรดติดต่อฉัน',
          ),
        );
      },
      child: Container(
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
            ? Image.asset('assets/images/user.png', fit: BoxFit.cover)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    Image.asset('assets/images/user.png', fit: BoxFit.cover),
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
