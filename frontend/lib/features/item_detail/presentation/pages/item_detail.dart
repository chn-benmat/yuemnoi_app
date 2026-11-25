import 'dart:async';

import 'package:frontend/core/widgets/app_popup.dart';
import '../../../rental_item/domain/entities/rental_item.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/widgets/pickup_location_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/auth_guard.dart';
import '../../../../core/navigation/item_deep_link.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../chat/domain/entities/item_inquiry_data.dart';
import '../../../../core/utils/phone_formatter.dart';
import '../../../../core/services/favorite_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/presentation/pages/profile/user_profile_view_screen.dart';
import '../../domain/entities/item_detail.dart';
import '../../domain/entities/related_item.dart';
import '../bloc/item_detail_bloc.dart';
import '../bloc/item_detail_event.dart';
import '../bloc/item_detail_state.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/review_content.dart';
import '../widgets/owner_item_controls.dart';
import '../widgets/owner_item_detail_view.dart';
import '../widgets/owner_item_detail_loading_view.dart';

// ใช้ม่วงแบรนด์เป็นจุดนำสายตา และพื้นสีอ่อนช่วยแยกข้อมูลโดยไม่แย่งรูปสินค้า
abstract final class _DetailStyle {
  static const accent = AppColors.primaryColor;
  static const surface = Colors.white;
  static const softSurface = Color(0xFFF7F3FC);
  static const accentSurface = Color(0xFFF0E5FC);
  static const ink = Color(0xFF241B32);
  static const secondary = Color(0xFF746B80);
  static const rule = Color(0xFFEDE7F3);
  static const favorite = Color(0xFFE33B70);
  static const shadow = Color(0x0A342047);

  static double galleryHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * .76).clamp(240.0, 340.0) +
      MediaQuery.paddingOf(context).top;
}

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.itemId,
    this.ownerLoadingLayout = false,
    this.preview = false,
    this.previewItem,
    this.previewPhotos,
  });

  final int itemId;
  final bool ownerLoadingLayout;
  final bool preview;
  final ItemDetail? previewItem;
  final List<RentalItemPhoto>? previewPhotos;

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
    FavoriteService.instance.favoritesNotifier.addListener(_syncFavoriteState);
    unawaited(FavoriteService.instance.init());
    unawaited(FavoriteService.instance.recordItemView(widget.itemId));
  }

  @override
  void dispose() {
    FavoriteService.instance.favoritesNotifier.removeListener(
      _syncFavoriteState,
    );
    super.dispose();
  }

  void _syncFavoriteState() {
    final isFavorite = FavoriteService.instance.isItemFavorite(widget.itemId);
    if (mounted && isFavorite != _isFavorite) {
      setState(() => _isFavorite = isFavorite);
    }
  }

  Future<void> _handleFavoriteToggle() async {
    late final bool isFav;
    try {
      isFav = await FavoriteService.instance.toggleFavorite(widget.itemId);
    } on FavoriteServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _isFavorite = isFav);
  }

  Future<void> _openEdit(ItemDetail item) async {
    final updated = await AppRoutes.openEditRentalItem(context, item: item);
    if (updated == true && mounted) {
      context.read<ItemDetailBloc>().add(ItemDetailRequested(widget.itemId));
    }
  }

  Future<void> _deleteItem(ItemDetail item) async {
    final confirmed = await confirmItemDeletion(context, item.name);
    if (confirmed && mounted) {
      context.read<ItemDetailBloc>().add(const ItemDeleteSubmitted());
    }
  }

  Future<void> _refreshItem() async {
    final bloc = context.read<ItemDetailBloc>();
    if (bloc.state.isBusy) return;
    final completed = bloc.stream.firstWhere((state) => !state.isBusy);
    bloc.add(ItemDetailRequested(widget.itemId));
    await completed;
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

      // เปิดแชตซ้ำโดยไม่ส่งความสนใจเพิ่ม จนกว่ารายการเช่ารอบเดิมจะปิด
      final chatDataSource = ChatRemoteDataSource();
      String? initialMessageId;
      try {
        initialMessageId = await chatDataSource.sendItemInquiryIfNeeded(
          conversationId: conversation.id,
          inquiry: inquiryData,
          imageUrl: firstImageUrl.isNotEmpty ? firstImageUrl : null,
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _isChatLoading = false);
        await AppRoutes.openConversation(
          context,
          conversation: conversation,
          initialMessageId: initialMessageId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isChatLoading = false);
        showAppPopup(context, content: Text(e.toString()));
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
                    _submitComplaint();
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
                    _submitComplaint();
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
                    _submitComplaint();
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
                    _submitComplaint();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitComplaint() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อรายงานปัญหา',
      message: 'กรุณาเข้าสู่ระบบก่อนส่งเรื่องให้เจ้าหน้าที่ตรวจสอบ',
    );
    if (!authed || !mounted) return;
    final controller = TextEditingController();
    final description = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('รายละเอียดปัญหา'),
        content: TextField(
          controller: controller,
          maxLength: 2000,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText:
                'อธิบายปัญหาอย่างน้อย 5 ตัวอักษร ไม่ใส่เลขบัตรหรือข้อมูลส่วนตัว',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().length >= 5) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('ส่งรายงาน'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (description == null || !mounted) return;
    final api = DioApiClient();
    String message;
    try {
      final response = await api.post(
        '/api/complaints',
        headers: {'Authorization': 'Bearer ${AuthSession.accessToken}'},
        data: {'item_id': widget.itemId, 'description': description},
      );
      message = response.statusCode >= 200 && response.statusCode < 300
          ? 'ส่งรายงานปัญหาให้ทีมงานตรวจสอบเรียบร้อยแล้ว'
          : response.data is Map && response.data['error'] is String
          ? response.data['error']
          : 'ส่งรายงานไม่สำเร็จ กรุณาลองใหม่';
    } catch (_) {
      message = 'เชื่อมต่อระบบไม่ได้ กรุณาลองใหม่';
    } finally {
      api.close();
    }
    if (!mounted) return;
    if (message == 'ส่งรายงานปัญหาให้ทีมงานตรวจสอบเรียบร้อยแล้ว') {
      return;
    }
    showAppPopup(context, content: Text(message));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ItemDetailBloc, ItemDetailState>(
      listener: (context, state) {
        if (state.status == ItemDetailStatus.deleted) {
          AppRoutes.pop(context);
        } else if (state.status == ItemDetailStatus.failure &&
            state.item != null) {
          showAppPopup(
            context,
            content: Text(state.errorMessage ?? 'เกิดข้อผิดพลาด กรุณาลองใหม่'),
          );
        }
      },
      builder: (context, loadedState) {
        final state = widget.previewItem == null
            ? loadedState
            : loadedState.copyWith(item: widget.previewItem);
        final item = state.item;
        if (item == null && widget.ownerLoadingLayout) {
          return _ownerLayout(
            state.status == ItemDetailStatus.initial ||
                    state.status == ItemDetailStatus.loading
                ? const OwnerItemDetailLoadingView()
                : _LoadError(
                    message:
                        state.errorMessage ?? 'โหลดรายละเอียดอุปกรณ์ไม่สำเร็จ',
                    onRetry: () => context.read<ItemDetailBloc>().add(
                      ItemDetailRequested(widget.itemId),
                    ),
                  ),
          );
        }
        if (item != null && item.isOwner && !widget.preview) {
          return _ownerLayout(
            OwnerItemDetailView(
              item: item,
              busy: state.isBusy,
              deleting: state.status == ItemDetailStatus.deleting,
              onRefresh: _refreshItem,
              onVisibilityChanged: (visible) => context
                  .read<ItemDetailBloc>()
                  .add(ItemVisibilityChanged(hidden: !visible)),
              onEditBasic: () => _openEdit(item),
              onAutoReply: () =>
                  AppRoutes.openItemAutoReply(context, item: item),
              onDelete: () => _deleteItem(item),
            ),
          );
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: _DetailStyle.surface,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: _DetailStyle.surface,
            bottomNavigationBar: item == null
                ? null
                : _ChatActionBar(
                    item: item,
                    isLoading: _isChatLoading,
                    onPressed: state.isBusy || item.isOwner
                        ? null
                        : () => _openChat(item),
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
                    onFavorite: widget.previewItem != null || item == null
                        ? null
                        : _handleFavoriteToggle,
                    onShare: widget.previewItem != null || item == null
                        ? null
                        : () => _handleShare(item),
                    onReport: widget.previewItem != null || item == null
                        ? null
                        : () => _openReportOptions(item),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ownerLayout(Widget child) => Scaffold(
    backgroundColor: const Color(0xFFF7F6FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      foregroundColor: const Color(0xFF211C35),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        tooltip: 'ย้อนกลับ',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => AppRoutes.pop(context),
      ),
      title: const Text(
        'รายละเอียดอุปกรณ์',
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    body: SafeArea(top: false, child: child),
  );

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
        if (widget.previewItem != null) return;
        context.read<ItemDetailBloc>().add(ItemDetailRequested(widget.itemId));
        await context.read<ItemDetailBloc>().stream.firstWhere(
          (next) => next.status != ItemDetailStatus.loading,
        );
      },
      child: CustomScrollView(
        key: const ValueKey('item-detail-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _ImageGallery(
                  imageUrls: item.imageUrls,
                  photos: widget.previewPhotos,
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: _DetailContent(
                    item: item,
                    relatedItems: state.relatedItems,
                    relatedStatus: state.relatedStatus,
                  ),
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
    final galleryHeight = _DetailStyle.galleryHeight(context);

    return SkeletonShimmer(
      key: const ValueKey('item-detail-skeleton'),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SkeletonBox(height: galleryHeight, borderRadius: 0),
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  color: _DetailStyle.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 24, borderRadius: 8),
                    SizedBox(height: 12),
                    SkeletonBox(width: 250, height: 30, borderRadius: 8),
                    SizedBox(height: 24),
                    SkeletonBox(width: 130, height: 18, borderRadius: 8),
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
                    SizedBox(height: 24),
                    _OwnerCardSkeleton(),
                    SizedBox(height: 28),
                    SkeletonBox(width: 92, height: 15, borderRadius: 8),
                    SizedBox(height: 18),
                    SkeletonBox(
                      width: double.infinity,
                      height: 80,
                      borderRadius: 16,
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
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _DetailStyle.surface,
        border: Border.all(color: _DetailStyle.accentSurface),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          SkeletonBox(height: 44, width: 44, shape: BoxShape.circle),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 82, height: 12, borderRadius: 6),
                SizedBox(height: 6),
                SkeletonBox(width: 100, height: 16, borderRadius: 8),
              ],
            ),
          ),
          SizedBox(width: 12),
          SkeletonBox(width: 72, height: 14, borderRadius: 6),
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
  final VoidCallback? onFavorite;
  final VoidCallback? onShare;
  final VoidCallback? onReport;

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
              iconColor: isFavorite ? _DetailStyle.favorite : _DetailStyle.ink,
              onPressed: onFavorite,
            ),
            const SizedBox(width: 8),
            Container(
              decoration: _CircleActionButton.decoration,
              child: PopupMenuButton<String>(
                tooltip: 'เพิ่มเติม',
                enabled: onReport != null,
                icon: const Icon(Icons.more_horiz_rounded),
                iconColor: _DetailStyle.ink,
                color: _DetailStyle.surface,
                surfaceTintColor: _DetailStyle.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (_) => onReport?.call(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('รายงานปัญหา'),
                      ],
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

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconColor = _DetailStyle.ink,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color iconColor;
  final double iconSize;

  static final decoration = BoxDecoration(
    color: _DetailStyle.surface,
    shape: BoxShape.circle,
    border: Border.all(color: _DetailStyle.rule),
    boxShadow: const [
      BoxShadow(
        color: _DetailStyle.shadow,
        blurRadius: 12,
        offset: Offset(0, 3),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: decoration,
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
  const _ImageGallery({required this.imageUrls, this.photos});

  final List<RentalItemPhoto>? photos;

  final List<String> imageUrls;

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant _ImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.imageUrls, widget.imageUrls)) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final urls =
        widget.photos?.map((photo) => photo.remoteUrl ?? '').toList() ??
        widget.imageUrls;
    final galleryHeight = _DetailStyle.galleryHeight(context);

    return Container(
      height: galleryHeight,
      color: _DetailStyle.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (urls.isEmpty)
            const ColoredBox(
              color: _DetailStyle.softSurface,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: _DetailStyle.secondary,
                  size: 58,
                ),
              ),
            )
          else
            PageView.builder(
              key: ValueKey('item-image-gallery-${urls.join('|')}'),
              itemCount: urls.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + 20,
                  16,
                  36,
                ),
                child: Semantics(
                  button: true,
                  label:
                      'ดูรูปสินค้า ${index + 1} จาก ${urls.length} แบบเต็มจอ',
                  child: GestureDetector(
                    onTap: widget.photos != null
                        ? null
                        : () => FullScreenImageViewer.open(
                            context,
                            imageUrls: urls,
                            initialIndex: index,
                          ),
                    child: widget.photos?[index].localImage != null
                        ? Image.memory(
                            widget.photos![index].localImage!.bytes,
                            fit: BoxFit.contain,
                          )
                        : CachedNetworkImage(
                            imageUrl: urls[index],
                            fit: BoxFit.contain,
                            placeholder: (context, url) =>
                                const SkeletonShimmer(
                                  child: SkeletonBox(
                                    height: double.infinity,
                                    borderRadius: 16,
                                  ),
                                ),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: _DetailStyle.secondary,
                                size: 58,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),

          if (urls.length > 1)
            Positioned(
              right: 20,
              bottom: 34,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _DetailStyle.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _DetailStyle.rule),
                ),
                child: Text(
                  '${_page + 1}/${urls.length}',
                  style: const TextStyle(
                    color: _DetailStyle.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
  const _DetailContent({
    required this.item,
    required this.relatedItems,
    required this.relatedStatus,
  });

  final ItemDetail item;
  final List<RelatedItem> relatedItems;
  final RelatedItemsStatus relatedStatus;

  @override
  Widget build(BuildContext context) {
    final location = item.pickupLocation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Material(
        color: _DetailStyle.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _DetailStyle.accentSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _DetailStyle.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.name,
                  style: const TextStyle(
                    color: _DetailStyle.ink,
                    fontSize: 26,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    button: true,
                    label: 'เปิดจุดนัดรับ ${location.name} ใน Google Maps',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          openPickupLocationInGoogleMaps(context, location),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: _DetailStyle.accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                location.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _DetailStyle.secondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: _DetailStyle.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionTitle('รายละเอียดสินค้า'),
                const SizedBox(height: 12),
                _ExpandableDescription(
                  key: ValueKey('item-description-${item.id}'),
                  description: item.description,
                ),
                const SizedBox(height: 18),
                _OwnerCard(item: item),
                const SizedBox(height: 24),
                _ReviewsSection(
                  key: ValueKey('reviews-${item.id}'),
                  reviews: item.reviews,
                ),
                if (relatedStatus != RelatedItemsStatus.initial) ...[
                  const SizedBox(height: 24),
                  const Divider(color: _DetailStyle.rule, height: 1),
                  const SizedBox(height: 24),
                  _RelatedItemsSection(
                    items: relatedItems,
                    status: relatedStatus,
                    onRetry: () => context.read<ItemDetailBloc>().add(
                      ItemRelatedItemsRequested(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RentalPrice extends StatelessWidget {
  const _RentalPrice({required this.item});

  final ItemDetail item;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      '฿${NumberFormat.decimalPattern().format(item.price)}',
      style: const TextStyle(
        color: _DetailStyle.ink,
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ChatActionBar extends StatelessWidget {
  const _ChatActionBar({
    required this.item,
    required this.isLoading,
    required this.onPressed,
  });
  final ItemDetail item;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('item-chat-action-bar'),
    decoration: const BoxDecoration(
      color: _DetailStyle.surface,
      border: Border(top: BorderSide(color: _DetailStyle.rule)),
      boxShadow: [
        BoxShadow(
          color: _DetailStyle.shadow,
          blurRadius: 20,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ค่าเช่า / ${item.unitLabel}',
                        style: const TextStyle(
                          color: _DetailStyle.secondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _RentalPrice(item: item),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 6,
                  child: SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: isLoading ? null : onPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: _DetailStyle.accent,
                        foregroundColor: _DetailStyle.surface,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _DetailStyle.surface,
                              ),
                            )
                          : const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'แชทสอบถาม',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({super.key, required this.description});
  final String description;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final description = widget.description.trim().isEmpty
        ? 'ไม่มีคำอธิบายเพิ่มเติม'
        : widget.description.trim();
    const style = TextStyle(
      color: _DetailStyle.secondary,
      fontSize: 14,
      height: 1.7,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: description,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              maxLines: _expanded ? null : 3,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: style,
            ),
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: _DetailStyle.accent,
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(48, 48),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'ย่อรายละเอียด' : 'อ่านเพิ่มเติม',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.item});
  final ItemDetail item;

  @override
  Widget build(BuildContext context) {
    final owner = item.owner;
    return Material(
      color: _DetailStyle.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _DetailStyle.accentSurface),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => AppRoutes.openUserProfile(
          context,
          args: UserProfileViewArgs(
            userId: owner.userId,
            displayName: owner.displayName,
            avatarUrl: owner.imageUrl,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Avatar(imageUrl: owner.imageUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ปล่อยเช่าโดย',
                      style: TextStyle(
                        color: _DetailStyle.secondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      owner.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _DetailStyle.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (owner.isVerified) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (owner.isVerified) ...[
                            const Icon(
                              Icons.verified_rounded,
                              size: 13,
                              color: _DetailStyle.accent,
                            ),
                            const SizedBox(width: 4),
                          ],
                          const Expanded(
                            child: Text(
                              'ยืนยันตัวตนแล้ว',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _DetailStyle.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ดูโปรไฟล์',
                    style: TextStyle(
                      color: _DetailStyle.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _DetailStyle.accent,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelatedItemsSection extends StatelessWidget {
  const _RelatedItemsSection({
    required this.items,
    required this.status,
    required this.onRetry,
  });
  final List<RelatedItem> items;
  final RelatedItemsStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('สินค้าใกล้เคียง'),
      const SizedBox(height: 14),
      if (status == RelatedItemsStatus.failure)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DetailStyle.softSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'โหลดสินค้าใกล้เคียงไม่สำเร็จ',
                style: TextStyle(color: _DetailStyle.secondary, fontSize: 13),
              ),
              TextButton(onPressed: onRetry, child: const Text('ลองอีกครั้ง')),
            ],
          ),
        )
      else if (status == RelatedItemsStatus.loaded && items.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _DetailStyle.softSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.category_outlined,
                color: _DetailStyle.secondary,
                size: 24,
              ),
              SizedBox(height: 8),
              Text(
                'ยังไม่มีสินค้าอื่นในหมวดนี้',
                textAlign: TextAlign.center,
                style: TextStyle(color: _DetailStyle.secondary, fontSize: 13),
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth * .54).clamp(144.0, 180.0);
            final scaler = MediaQuery.textScalerOf(context);
            final nameHeight = scaler.scale(13) * 1.4 * 2;
            final priceHeight = scaler.scale(17) * 1.4;
            final height = width + nameHeight + priceHeight + 36;
            if (status == RelatedItemsStatus.loading) {
              return SkeletonShimmer(
                child: SizedBox(
                  height: height,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 2,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, _) => SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: width, borderRadius: 16),
                          const SizedBox(height: 12),
                          const SkeletonBox(
                            width: 120,
                            height: 14,
                            borderRadius: 6,
                          ),
                          const SizedBox(height: 8),
                          const SkeletonBox(
                            width: 80,
                            height: 18,
                            borderRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return SizedBox(
              height: height,
              child: ListView.separated(
                key: const ValueKey('related-items-list'),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: width,
                    child: _RelatedItemCard(
                      item: item,
                      nameHeight: nameHeight,
                      priceHeight: priceHeight,
                    ),
                  );
                },
              ),
            );
          },
        ),
    ],
  );
}

class _RelatedItemCard extends StatelessWidget {
  const _RelatedItemCard({
    required this.item,
    required this.nameHeight,
    required this.priceHeight,
  });
  final RelatedItem item;
  final double nameHeight;
  final double priceHeight;

  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('related-item-${item.id}'),
    color: _DetailStyle.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _DetailStyle.rule),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => AppRoutes.openItemDetail(context, itemId: item.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: item.imageUrl.isEmpty
                ? const ColoredBox(
                    color: _DetailStyle.softSurface,
                    child: Icon(
                      Icons.image_outlined,
                      color: _DetailStyle.secondary,
                      size: 32,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, _) =>
                        const ColoredBox(color: _DetailStyle.softSurface),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.image_outlined,
                      color: _DetailStyle.secondary,
                      size: 32,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: nameHeight,
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _DetailStyle.ink,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: priceHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '฿${NumberFormat.decimalPattern().format(item.price)}',
                          style: const TextStyle(
                            color: _DetailStyle.accent,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ ${item.unitLabel}',
                          style: const TextStyle(
                            color: _DetailStyle.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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

class _ReviewsSection extends StatefulWidget {
  const _ReviewsSection({super.key, required this.reviews});
  final List<ItemReview> reviews;

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _showingMore = false;

  int get _count => widget.reviews.take(4).length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _ReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.reviews, widget.reviews)) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    final media = MediaQuery.of(context);
    if (_count < 2 || media.disableAnimations || media.accessibleNavigation)
      return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_controller.hasClients ||
          _showingMore ||
          !TickerMode.valuesOf(context).enabled ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          _controller.position.isScrollingNotifier.value)
        return;
      _controller.animateToPage(
        (_page + 1) % _count,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _showMore() async {
    _showingMore = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _AllReviewsPage(reviews: widget.reviews),
      ),
    );
    if (!mounted) return;
    _showingMore = false;
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: _SectionTitle('รีวิวจากคนที่เช่า')),
          if (widget.reviews.isNotEmpty)
            TextButton(onPressed: _showMore, child: const Text('ดูเพิ่มเติม')),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        widget.reviews.isEmpty
            ? 'ประสบการณ์เป็นยังไง มาแชร์กันได้เลย'
            : 'อ่านประสบการณ์ก่อนตัดสินใจ · ปัดดูรีวิวได้',
        style: const TextStyle(
          color: _DetailStyle.secondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      if (widget.reviews.isEmpty)
        const _EmptyReviews()
      else ...[
        SizedBox(
          height: 300 * MediaQuery.textScalerOf(context).scale(1),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _timer?.cancel();
              } else if (notification is ScrollEndNotification) {
                _restartTimer();
              }
              return false;
            },
            child: PageView.builder(
              key: const ValueKey('review-carousel'),
              controller: _controller,
              itemCount: _count,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: SingleChildScrollView(
                  child: _ReviewCard(review: widget.reviews[index]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${_page + 1} / $_count',
            style: const TextStyle(color: _DetailStyle.secondary, fontSize: 12),
          ),
        ),
      ],
    ],
  );
}

class _AllReviewsPage extends StatefulWidget {
  const _AllReviewsPage({required this.reviews});
  final List<ItemReview> reviews;

  @override
  State<_AllReviewsPage> createState() => _AllReviewsPageState();
}

class _AllReviewsPageState extends State<_AllReviewsPage> {
  int? _stars;

  @override
  Widget build(BuildContext context) {
    final reviews = widget.reviews
        .where((review) => _stars == null || review.rating.round() == _stars)
        .toList();
    return Scaffold(
      backgroundColor: _DetailStyle.surface,
      appBar: AppBar(title: const Text('รีวิวทั้งหมด')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  for (final stars in <int?>[null, 5, 4, 3, 2, 1])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(stars == null ? 'ทั้งหมด' : '$stars ดาว'),
                        selected: _stars == stars,
                        onSelected: (_) => setState(() => _stars = stars),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                '${reviews.length} รีวิว',
                style: const TextStyle(color: _DetailStyle.secondary),
              ),
            ),
            Expanded(
              child: reviews.isEmpty
                  ? const Center(child: Text('ยังไม่มีรีวิวในระดับดาวนี้'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: reviews.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) =>
                          _ReviewCard(review: reviews[index]),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _DetailStyle.surface,
        border: Border.all(color: _DetailStyle.rule),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(imageUrl: review.reviewer.imageUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  review.reviewer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _DetailStyle.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'ให้คะแนน ${review.rating.toStringAsFixed(1)} จาก 5 ดาว',
            excludeSemantics: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Stars(rating: review.rating),
                Text(
                  '${review.rating.toStringAsFixed(1)}/5',
                  style: const TextStyle(
                    color: _DetailStyle.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (review.description.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            ReviewContent(description: review.description),
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
          color: _DetailStyle.accent,
          size: 16,
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
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _DetailStyle.accentSurface),
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
      color: _DetailStyle.ink,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: _DetailStyle.softSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.rate_review_outlined,
            color: _DetailStyle.secondary,
            size: 24,
          ),
          SizedBox(height: 8),
          Text(
            'ยังไม่มีรีวิว มารอรีวิวแรกกัน',
            style: TextStyle(color: _DetailStyle.secondary, fontSize: 13),
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
