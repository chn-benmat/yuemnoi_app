import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

/// ข้อมูลสำหรับแสดงโปรไฟล์สาธารณะของผู้ใช้คนอื่น
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

class UserProfileViewScreen extends StatelessWidget {
  final UserProfileViewArgs args;

  const UserProfileViewScreen({super.key, required this.args});

  static const _mockFeaturedItems = [
    _RentalItemData(
      title: 'Sony A7 IV',
      pricePerDay: 100,
      rating: 4.9,
      iconData: Icons.camera_alt_outlined,
      colorSeed: Color(0xFF1A0038),
    ),
    _RentalItemData(
      title: 'DJI Mavic Pro',
      pricePerDay: 100,
      rating: 0.0,
      iconData: Icons.flight_takeoff_outlined,
      colorSeed: Color(0xFF00112B),
    ),
  ];

  static const _mockAllItems = [
    _RentalItemData(
      title: 'Canon EOS',
      pricePerDay: 150,
      rating: 4.2,
      iconData: Icons.camera_outlined,
      colorSeed: Color(0xFF1A0038),
    ),
    _RentalItemData(
      title: 'เสื้อสูทผู้ชาย Essential',
      pricePerDay: 250,
      rating: 1.0,
      iconData: Icons.checkroom_outlined,
      colorSeed: Color(0xFF152030),
    ),
    _RentalItemData(
      title: 'Sony A7 IV',
      pricePerDay: 100,
      rating: 5.0,
      iconData: Icons.camera_alt_outlined,
      colorSeed: Color(0xFF1A0038),
    ),
    _RentalItemData(
      title: 'DJI Mavic Pro',
      pricePerDay: 100,
      rating: 0.0,
      iconData: Icons.flight_takeoff_outlined,
      colorSeed: Color(0xFF00112B),
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile header ───────────────────────────────────
            _ProfileHeaderSection(args: args),

            const SizedBox(height: 20),

            // ── Featured rentals ─────────────────────────────────
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
                itemCount: _mockFeaturedItems.length,
                separatorBuilder: (context, i) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _RentalCard(
                  item: _mockFeaturedItems[index],
                  width: 158,
                ),
              ),
            ),

            const SizedBox(height: 22),

            // ── All items grid ───────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'อุปกรณ์ที่ปล่อยเช่าทั้งหมด',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: _mockAllItems.length,
              itemBuilder: (context, index) =>
                  _RentalCard(item: _mockAllItems[index]),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeaderSection extends StatelessWidget {
  final UserProfileViewArgs args;
  const _ProfileHeaderSection({required this.args});

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
            avatarUrl: args.avatarUrl,
            displayName: args.displayName,
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            args.displayName,
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
              if (args.isVerified) ...[
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
                label: args.rating.toStringAsFixed(1),
                iconColor: const Color(0xFFFF9800),
                textColor: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ],
          ),

          // Bio
          if (args.bio != null && args.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              args.bio!,
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

          // Chat button
          ElevatedButton(
            onPressed: () {},
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
              'แชทกับ ${args.displayName}',
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
      width: 100,
      height: 100,
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
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
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
  final String title;
  final double pricePerDay;
  final double rating;
  final IconData iconData;
  final Color colorSeed;

  const _RentalItemData({
    required this.title,
    required this.pricePerDay,
    required this.rating,
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
      onTap: () {},
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
                      // Background
                      Container(
                        color: item.colorSeed,
                        child: Center(
                          child: Icon(
                            item.iconData,
                            color: Colors.white.withValues(alpha: 0.5),
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
                                color: Color(0xFFFFD54F),
                                size: 11,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.rating.toStringAsFixed(1),
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
              // ── Title ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
