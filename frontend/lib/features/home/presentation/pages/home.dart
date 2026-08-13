import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/custom_bottom_navbar.dart';
import '../../../chat/presentation/pages/chat.dart';
import '../../../profile/presentation/pages/profile.dart';
import '../../../wallet/presentation/pages/wallet.dart';
import 'home_feed_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomeFeedView(),
    ChatScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      floatingActionButton: _selectedIndex == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 56,
                  child: FloatingActionButton(
                    key: const Key('home-add-rental-item-button'),
                    heroTag: 'add-rental-item-fab',
                    tooltip: 'เพิ่มอุปกรณ์ให้เช่า',
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    onPressed: () => AppRoutes.openAddRentalItem(context),
                    child: const Icon(Icons.add_rounded, size: 34),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox.square(
                  dimension: 64,
                  child: FloatingActionButton(
                    heroTag: 'chatbot-fab',
                    tooltip: 'แชตบอต',
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    onPressed: () => AppRoutes.openChatbot(context),
                    child: const Icon(Icons.smart_toy_rounded, size: 34),
                  ),
                ),
              ],
            )
          : null,
      bottomNavigationBar: CustomBottomNavbar(
        selectedIndex: _selectedIndex,
        onTabChange: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
