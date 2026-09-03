import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

/// ข้อมูลสำหรับแสดงโปรไฟล์สาธารณะของผู้ใช้
class UserProfileViewArgs {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double rating;
  final bool isVerified;
  final String? bio;

  const UserProfileViewArgs({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.rating = 0.0,
    this.isVerified = false,
    this.bio,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class UserProfileViewScreen extends StatefulWidget {
  final UserProfileViewArgs args;

  const UserProfileViewScreen({super.key, required this.args});

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  bool _isLoading = true;
  String _displayName = '';
  String? _avatarUrl;
  String? _bio;
  double _rating = 0.0;
  bool _isVerified = false;

  List<_RentalItemData> _featuredItems = [];
  List<_RentalItemData> _userItems = [];

  @override
  void initState() {
    super.initState();
    _displayName = widget.args.displayName;
    _avatarUrl = widget.args.avatarUrl;
    _bio = widget.args.bio;
    _rating = widget.args.rating > 0 ? widget.args.rating : 4.9;
    _isVerified = widget.args.isVerified;

    _loadSupabaseData();
  }

  Future<void> _loadSupabaseData() async {
    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final client = SupabaseConfig.client;
    final currentUser = client.auth.currentUser;
    final targetUserId = widget.args.userId.isNotEmpty
        ? widget.args.userId
        : currentUser?.id ?? '';

    try {
      // 1. ดึงข้อมูลโปรไฟล์ล่าสุดของผู้ใช้จาก Supabase
      if (targetUserId.isNotEmpty) {
        try {
          final profileResp = await client
              .from('profile_tb')
              .select('user_id, user_image_url')
              .eq('user_id', targetUserId)
              .maybeSingle();

          if (profileResp != null && mounted) {
            final img = profileResp['user_image_url'] as String?;
            if (img != null && img.trim().isNotEmpty) {
              _avatarUrl = img.trim();
            }
          }
        } catch (_) {}

        // ถ้าเป็นผู้ใช้ปัจจุบัน นำ metadata จาก Auth มาเสริม
        if (currentUser != null && currentUser.id == targetUserId) {
          final meta = currentUser.userMetadata ?? {};
          final name = meta['display_name'] as String? ??
              meta['full_name'] as String? ??
              currentUser.email?.split('@').first;
          if (name != null && name.isNotEmpty) _displayName = name;
          final bio = meta['bio'] as String?;
          if (bio != null && bio.isNotEmpty) _bio = bio;
          final avatar =
              meta['avatar_url'] as String? ?? meta['picture'] as String?;
          if (avatar != null && avatar.isNotEmpty) _avatarUrl = avatar;
        }
      }

      // 2. ดึงรายการอุปกรณ์จริงที่เป็นของผู้ใช้นี้ (user_id = targetUserId)
      List<_RentalItemData> loadedUserItems = [];
      if (targetUserId.isNotEmpty) {
        try {
          final userItemsResp = await client
              .from('item_tb')
              .select(
                  'id, user_id, item_name, item_image_url, description, category, price, status')
              .eq('user_id', targetUserId)
              .order('id', ascending: false);

          loadedUserItems = _parseItems(userItemsResp);
        } catch (_) {}
      }

      // 3. ดึงรายการแนะนำที่น่าสนใจ (Marketplace featured items) จาก Supabase
      List<_RentalItemData> loadedFeatured = [];
      try {
        final featuredResp = await client
            .from('item_tb')
            .select(
                'id, user_id, item_name, item_image_url, description, category, price, status')
            .order('id', ascending: false)
            .limit(10);

        loadedFeatured = _parseItems(featuredResp);
      } catch (_) {}

      // 4. ดึงคะแนนรีวิวจริงจาก review_tb ถ้ามี
      if (loadedUserItems.isNotEmpty) {
        try {
          final itemIds =
              loadedUserItems.map((e) => e.id).whereType<int>().toList();
          if (itemIds.isNotEmpty) {
            final reviewsResp = await client
                .from('review_tb')
                .select('rating')
                .inFilter('item_id', itemIds);

            if (reviewsResp.isNotEmpty) {
              double sum = 0;
              int count = 0;
              for (final r in reviewsResp) {
                if (r['rating'] is num) {
                  sum += (r['rating'] as num).toDouble();
                  count++;
                }
              }
              if (count > 0) {
                _rating = (sum / count);
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _userItems = loadedUserItems;
          _featuredItems = loadedFeatured;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_RentalItemData> _parseItems(List rawList) {
    final List<_RentalItemData> result = [];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] as num?)?.toInt();
      final title = item['item_name']?.toString() ?? 'อุปกรณ์';
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final category = item['category']?.toString() ?? '';
      final imageUrl = _extractFirstImageUrl(item['item_image_url']);
      final (iconData, colorSeed) = _mapCategoryToStyle(category);

      result.add(
        _RentalItemData(
          id: id,
          title: title,
          pricePerDay: price,
          rating: 4.9,
          imageUrl: imageUrl,
          iconData: iconData,
          colorSeed: colorSeed,
        ),
      );
    }
    return result;
  }

  String? _extractFirstImageUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      for (final el in raw) {
        if (el != null && el.toString().trim().isNotEmpty) {
          return el.toString().trim();
        }
      }
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.first.toString().trim();
          }
        } catch (_) {}
      }
      return trimmed;
    }
    return null;
  }

  (IconData, Color) _mapCategoryToStyle(String? category) {
    if (category == null) {
      return (Icons.devices_other_outlined, const Color(0xFF1A1A2E));
    }
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera')) {
      return (Icons.camera_alt_outlined, const Color(0xFF1A0038));
    }
    if (cat.contains('โดรน') || cat.contains('drone')) {
      return (Icons.flight_takeoff_outlined, const Color(0xFF00112B));
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone')) {
      return (Icons.smartphone_outlined, const Color(0xFF0F172A));
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook')) {
      return (Icons.laptop_mac_outlined, const Color(0xFF1E1B4B));
    }
    if (cat.contains('เสียง') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio')) {
      return (Icons.speaker_outlined, const Color(0xFF14532D));
    }
    if (cat.contains('แคมป์') || cat.contains('เต็นท์')) {
      return (Icons.terrain_outlined, const Color(0xFF064E3B));
    }
    if (cat.contains('รถ') || cat.contains('ยานยนต์')) {
      return (Icons.directions_car_outlined, const Color(0xFF1C1917));
    }
    if (cat.contains('เครื่องมือ') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tool')) {
      return (Icons.build_outlined, const Color(0xFF312E81));
    }
    if (cat.contains('เสื้อ') || cat.contains('สูท')) {
      return (Icons.checkroom_outlined, const Color(0xFF152030));
    }
    return (Icons.inventory_2_outlined, const Color(0xFF2E1065));
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    final isCurrentUser = currentUid != null &&
        currentUid.isNotEmpty &&
        currentUid == widget.args.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryColor, AppColors.gradient1],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'Yuemnoi',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadSupabaseData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Profile header ───────────────────────────────────
                    _ProfileHeaderSection(
                      displayName: _displayName,
                      avatarUrl: _avatarUrl,
                      bio: _bio,
                      rating: _rating,
                      isVerified: _isVerified,
                      isCurrentUser: isCurrentUser,
                      onEditProfile: () async {
                        await AppRoutes.openEditProfile(context);
                        _loadSupabaseData();
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── Featured rentals (Marketplace) ───────────────────
                    if (_featuredItems.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'รายการเช่าที่น่าสนใจสำหรับคุณ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 192,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _featuredItems.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) => _RentalCard(
                            item: _featuredItems[index],
                            width: 158,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],

                    // ── All items grid (User's items) ───────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'อุปกรณ์ที่ปล่อยเช่าทั้งหมด',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          if (_userItems.isNotEmpty)
                            Text(
                              '${_userItems.length} รายการ',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: AppColors.hintTextColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_userItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF3E8FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: AppColors.primaryColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                isCurrentUser
                                    ? 'คุณยังไม่มีอุปกรณ์ที่ปล่อยเช่า'
                                    : 'ยังไม่มีอุปกรณ์ที่ปล่อยเช่าในขณะนี้',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isCurrentUser
                                    ? 'นำอุปกรณ์ที่คุณมีมาปล่อยเช่าเพื่อสร้างรายได้ง่ายๆ'
                                    : 'ผู้ใช้นี้ยังไม่ได้ลงประกาศปล่อยเช่าอุปกรณ์ใดๆ',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  color: AppColors.hintTextColor,
                                ),
                              ),
                              if (isCurrentUser) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await AppRoutes.openAddRentalItem(context);
                                    _loadSupabaseData();
                                  },
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text(
                                    'ลงประกาศอุปกรณ์',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: _userItems.length,
                        itemBuilder: (context, index) =>
                            _RentalCard(item: _userItems[index]),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeaderSection extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final double rating;
  final bool isVerified;
  final bool isCurrentUser;
  final VoidCallback onEditProfile;

  const _ProfileHeaderSection({
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.rating,
    required this.isVerified,
    required this.isCurrentUser,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          // Avatar with gradient ring
          _GradientAvatar(
            avatarUrl: avatarUrl,
            displayName: displayName,
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            displayName,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 10),

          // Badges row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isVerified) ...[
                _InfoBadge(
                  icon: Icons.verified_rounded,
                  label: 'ยืนยันตัว',
                  iconColor: AppColors.primaryColor,
                  textColor: AppColors.primaryColor,
                  bgColor: const Color(0xFFF3E8FF),
                ),
                const SizedBox(width: 8),
              ],
              _InfoBadge(
                icon: Icons.star_rounded,
                label: rating > 0 ? rating.toStringAsFixed(1) : '5.0',
                iconColor: const Color(0xFFFF9800),
                textColor: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ],
          ),

          // Bio
          if (bio != null && bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.labelColor,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Action button
          ElevatedButton(
            onPressed: isCurrentUser ? onEditProfile : () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              isCurrentUser ? 'แก้ไขโปรไฟล์' : 'แชทกับ $displayName',
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Gradient Avatar ──────────────────────────────────────────────────────────

class _GradientAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;

  const _GradientAvatar({required this.avatarUrl, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 94,
      height: 94,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.gradient2, AppColors.primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(3.5),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.trim().isNotEmpty
            ? Image.network(
                avatarUrl!.trim(),
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) =>
                    _InitialCircle(name: displayName),
              )
            : _InitialCircle(name: displayName),
      ),
    );
  }
}

class _InitialCircle extends StatelessWidget {
  final String name;
  const _InitialCircle({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFFF3E8FF),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
        ),
      ),
    );
  }
}

// ─── Info Badge ───────────────────────────────────────────────────────────────

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final Color bgColor;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rental Item Card ─────────────────────────────────────────────────────────

class _RentalItemData {
  final int? id;
  final String title;
  final double pricePerDay;
  final double rating;
  final String? imageUrl;
  final IconData iconData;
  final Color colorSeed;

  const _RentalItemData({
    this.id,
    required this.title,
    required this.pricePerDay,
    required this.rating,
    this.imageUrl,
    required this.iconData,
    required this.colorSeed,
  });
}

class _RentalCard extends StatelessWidget {
  final _RentalItemData item;
  final double? width;

  const _RentalCard({required this.item, this.width});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.id != null) {
          AppRoutes.openItemDetail(context, itemId: item.id!);
        }
      },
      child: SizedBox(
        width: width,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image section ──────────────────────────────
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Real Image from Supabase or Fallback
                      if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                        Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => Container(
                            color: item.colorSeed,
                            child: Center(
                              child: Icon(
                                item.iconData,
                                color: Colors.white.withValues(alpha: 0.6),
                                size: 44,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: item.colorSeed,
                          child: Center(
                            child: Icon(
                              item.iconData,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 44,
                            ),
                          ),
                        ),
                      // Price badge (bottom left)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.pricePerDay.toInt()} ฿/วัน',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Rating badge (bottom right)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFF9800),
                                size: 12,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.rating > 0
                                    ? item.rating.toStringAsFixed(1)
                                    : '5.0',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Title section ──────────────────────────────
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
