import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/custom_bottom_navbar.dart';
import '../../../chat/presentation/pages/chat.dart';
import '../../../profile/presentation/pages/profile.dart';
import '../../../wallet/presentation/pages/wallet.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import 'home_feed_view.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final homeRepository = HomeRepositoryImpl();

    return BlocProvider<HomeBloc>(
      create: (context) => HomeBloc(
        homeRepository: homeRepository,
        getHomeFeed: GetHomeFeedUseCase(homeRepository),
      )..add(const LoadHomeFeedStarted()),
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  const _HomeScreenContent();

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
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
