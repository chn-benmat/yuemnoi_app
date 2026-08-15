import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class RentalStatusScreen extends StatefulWidget {
  const RentalStatusScreen({super.key});

  @override
  State<RentalStatusScreen> createState() => _RentalStatusScreenState();
}

class _RentalStatusScreenState extends State<RentalStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ข้อมูลตัวอย่าง — ฝั่งเช่า (Renter)
  final List<_StatusItemData> _rentingItems = const [
    _StatusItemData(
      title: 'Sony A7 IV',
      ownerName: 'คนที่ 3คนที่สาม',
      status: 'นัดรับของ',
      statusColor: Color(0xFFFFD54F),
      iconData: Icons.camera_alt_outlined,
    ),
    _StatusItemData(
      title: 'DJI Mavic Pro',
      ownerName: 'สกน จัสดี',
      status: 'กำลังรับของ',
      statusColor: Color(0xFF80DEEA),
      iconData: Icons.flight_takeoff_outlined,
    ),
    _StatusItemData(
      title: 'MacBook Pro M2',
      ownerName: 'สุกรา พล่วงเรียง',
      status: 'จัดส่งแล้ว',
      statusColor: Color(0xFFA5D6A7),
      iconData: Icons.laptop_mac_outlined,
    ),
  ];

  // ข้อมูลตัวอย่าง — ฝั่งปล่อยเช่า (Lender)
  final List<_StatusItemData> _lendingItems = const [
    _StatusItemData(
      title: 'Sony A7 IV',
      ownerName: 'คนที่ 3คนที่สาม',
      status: 'นัดรับของ',
      statusColor: Color(0xFFFFD54F),
      iconData: Icons.camera_alt_outlined,
    ),
    _StatusItemData(
      title: 'DJI Mavic Pro',
      ownerName: 'สกน จัสดี',
      status: 'กำลังรับของ',
      statusColor: Color(0xFF80DEEA),
      iconData: Icons.flight_takeoff_outlined,
    ),
    _StatusItemData(
      title: 'MacBook Pro M2',
      ownerName: 'สุกรา พล่วงเรียง',
      status: 'จัดส่งแล้ว',
      statusColor: Color(0xFFA5D6A7),
      iconData: Icons.laptop_mac_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'สถานะ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w400,
            fontSize: 15,
          ),
          tabs: const [
            Tab(text: 'เช่า'),
            Tab(text: 'ปล่อยเช่า'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _StatusList(items: _rentingItems),
          _StatusList(items: _lendingItems),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusItemData {
  final String title;
  final String ownerName;
  final String status;
  final Color statusColor;
  final IconData iconData;

  const _StatusItemData({
    required this.title,
    required this.ownerName,
    required this.status,
    required this.statusColor,
    required this.iconData,
  });
}

class _StatusList extends StatelessWidget {
  final List<_StatusItemData> items;
  const _StatusList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีรายการ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: AppColors.hintTextColor,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, i) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _StatusCard(item: items[index]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final _StatusItemData item;
  const _StatusCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF7400C9), Color(0xFF5200A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Top row: image + info + status ────────────────────
            Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 70,
                    height: 70,
                    color: const Color(0xFF3A0070),
                    child: Icon(item.iconData, color: Colors.white54, size: 28),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.ownerName,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: item.statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: item.statusColor.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    item.status,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      color: item.statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ── Check status button ────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text(
                  'ตรวจสอบสถานะ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
