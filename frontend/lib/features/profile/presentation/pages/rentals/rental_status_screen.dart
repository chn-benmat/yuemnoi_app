import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../widgets/rentals/rental_status_widgets.dart';

class RentalStatusScreen extends StatefulWidget {
  const RentalStatusScreen({super.key});

  @override
  State<RentalStatusScreen> createState() => _RentalStatusScreenState();
}

class _RentalStatusScreenState extends State<RentalStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ข้อมูลตัวอย่าง — ฝั่งเช่า (Renter)
  final List<RentalStatusItemData> _rentingItems = const [
    RentalStatusItemData(
      title: 'Sony A7 IV',
      ownerName: 'คนที่ 3คนที่สาม',
      status: 'นัดรับของ',
      statusColor: Color(0xFFFFD54F),
      iconData: Icons.camera_alt_outlined,
    ),
    RentalStatusItemData(
      title: 'DJI Mavic Pro',
      ownerName: 'สกน จัสดี',
      status: 'กำลังรับของ',
      statusColor: Color(0xFF80DEEA),
      iconData: Icons.flight_takeoff_outlined,
    ),
    RentalStatusItemData(
      title: 'MacBook Pro M2',
      ownerName: 'สุกรา พล่วงเรียง',
      status: 'จัดส่งแล้ว',
      statusColor: Color(0xFFA5D6A7),
      iconData: Icons.laptop_mac_outlined,
    ),
  ];

  // ข้อมูลตัวอย่าง — ฝั่งปล่อยเช่า (Lender)
  final List<RentalStatusItemData> _lendingItems = const [
    RentalStatusItemData(
      title: 'Sony A7 IV',
      ownerName: 'คนที่ 3คนที่สาม',
      status: 'นัดรับของ',
      statusColor: Color(0xFFFFD54F),
      iconData: Icons.camera_alt_outlined,
    ),
    RentalStatusItemData(
      title: 'DJI Mavic Pro',
      ownerName: 'สกน จัสดี',
      status: 'กำลังรับของ',
      statusColor: Color(0xFF80DEEA),
      iconData: Icons.flight_takeoff_outlined,
    ),
    RentalStatusItemData(
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
          RentalStatusList(items: _rentingItems),
          RentalStatusList(items: _lendingItems),
        ],
      ),
    );
  }
}
