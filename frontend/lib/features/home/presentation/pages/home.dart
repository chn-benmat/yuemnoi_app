import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/custom_bottom_navbar.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../chat/domain/usecases/get_conversations_usecase.dart';
import '../../../chat/presentation/bloc/chat_list_bloc.dart';
import '../../../chat/presentation/bloc/chat_list_event.dart';
import '../../../chat/presentation/bloc/chat_list_state.dart';
import '../../../chat/presentation/pages/chat.dart';
import '../../../profile/presentation/pages/profile/profile.dart';
import '../../../wallet/presentation/pages/wallet.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import '../bloc/home_bloc.dart';
import '../bloc/home_event.dart';
import 'home_feed_view.dart';

class HomeScreen extends StatelessWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    final homeRepository = HomeRepositoryImpl();
    final chatRepository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<HomeBloc>(
          create: (context) => HomeBloc(
            homeRepository: homeRepository,
            getHomeFeed: GetHomeFeedUseCase(homeRepository),
          )..add(const LoadHomeFeedStarted()),
        ),
        BlocProvider<ChatListBloc>(
          create: (context) => ChatListBloc(
            getConversations: GetConversationsUseCase(chatRepository),
          )..add(const LoadChatListStarted()),
        ),
      ],
      child: _HomeScreenContent(
        key: ValueKey('home_content_$initialIndex'),
        initialIndex: initialIndex,
      ),
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final int initialIndex;
  const _HomeScreenContent({super.key, this.initialIndex = 0});

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant _HomeScreenContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex ||
        _selectedIndex != widget.initialIndex) {
      setState(() {
        _selectedIndex = widget.initialIndex;
      });
    }
  }

  List<Widget> get _pages => [
        const HomeFeedView(),
        const ChatScreen(),
        WalletScreen(
          onBack: () {
            setState(() {
              _selectedIndex = 0;
            });
          },
        ),
        const ProfileScreen(),
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
      bottomNavigationBar: BlocBuilder<ChatListBloc, ChatListState>(
        builder: (context, chatState) {
          final hasUnread =
              chatState.conversations.any((c) => c.hasUnreadMessage);

          return CustomBottomNavbar(
            selectedIndex: _selectedIndex,
            hasUnreadChat: hasUnread,
            onTabChange: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          );
        },
      ),
    );
  }
}
