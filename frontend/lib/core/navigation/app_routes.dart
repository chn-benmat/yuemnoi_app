import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/change_password.dart';
import '../../features/auth/presentation/pages/forget_password.dart';
import '../../features/auth/presentation/pages/login.dart';
import '../../features/auth/presentation/pages/one_time_verification.dart';
import '../../features/auth/presentation/pages/register.dart';
import '../../features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import '../../features/chatbot/data/repositories/chatbot_repository_impl.dart';
import '../../features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import '../../features/chatbot/presentation/bloc/chatbot_bloc.dart';
import '../../features/chatbot/presentation/pages/chat_bot.dart';
import '../../features/chat/domain/entities/chat_conversation.dart';
import '../../features/chat/presentation/pages/chat_detail.dart';
import '../../features/item_detail/data/datasources/item_detail_remote_data_source.dart';
import '../../features/item_detail/data/repositories/item_detail_repository_impl.dart';
import '../../features/item_detail/domain/entities/item_detail.dart';
import '../../features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import '../../features/item_detail/domain/usecases/update_item_usecase.dart';
import '../../features/item_detail/presentation/bloc/item_detail_bloc.dart';
import '../../features/item_detail/presentation/bloc/item_detail_event.dart';
import '../../features/item_detail/presentation/pages/edit_item.dart';
import '../../features/item_detail/presentation/pages/item_detail.dart';
import '../../features/home/presentation/pages/home.dart';
import '../../features/rental_item/data/datasources/rental_item_remote_data_source.dart';
import '../../features/rental_item/data/repositories/rental_item_repository_impl.dart';
import '../../features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import '../../features/rental_item/presentation/bloc/rental_item_bloc.dart';
import '../../features/rental_item/presentation/pages/add_rental_item.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const chatbot = '/chatbot';
  static const chatDetail = '/chat/detail';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const otpVerification = '/otp-verification';
  static const changePassword = '/change-password';
  static const addRentalItem = '/rental-items/add';
  static const itemDetail = '/items/:itemId';
  static const editRentalItem = '/items/:itemId/edit';

  static GoRouter createRouter({String initialLocation = login}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: login,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const LoginScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: home,
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const HomeScreen(),
          ),
        ),
        GoRoute(
          path: chatbot,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (context) => ChatbotBloc(
                sendMessage: SendChatMessageUseCase(
                  ChatbotRepositoryImpl(ChatbotRemoteDataSource()),
                ),
              ),
              child: const ChatBotScreen(),
            ),
          ),
        ),
        GoRoute(
          path: chatDetail,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: ChatDetailScreen(
              conversation: _requiredConversationExtra(state),
            ),
          ),
        ),
        GoRoute(
          path: addRentalItem,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (context) => RentalItemBloc(
                createItem: CreateRentalItemUseCase(
                  RentalItemRepositoryImpl(RentalItemRemoteDataSource()),
                ),
              ),
              child: const AddRentalItemScreen(),
            ),
          ),
        ),
        GoRoute(
          path: itemDetail,
          pageBuilder: (context, state) {
            final itemId = _requiredItemId(state);
            final repository = ItemDetailRepositoryImpl(
              ItemDetailRemoteDataSource(),
            );
            return MaterialPage<void>(
              key: state.pageKey,
              child: BlocProvider(
                create: (context) => ItemDetailBloc(
                  getItem: GetItemDetailUseCase(repository),
                  updateItem: UpdateItemUseCase(repository),
                )..add(ItemDetailRequested(itemId)),
                child: ItemDetailScreen(itemId: itemId),
              ),
            );
          },
        ),
        GoRoute(
          path: editRentalItem,
          pageBuilder: (context, state) {
            final item = _requiredItemExtra(state);
            final repository = ItemDetailRepositoryImpl(
              ItemDetailRemoteDataSource(),
            );
            return MaterialPage<bool>(
              key: state.pageKey,
              child: BlocProvider(
                create: (context) => ItemDetailBloc(
                  getItem: GetItemDetailUseCase(repository),
                  updateItem: UpdateItemUseCase(repository),
                  initialItem: item,
                ),
                child: EditItemScreen(item: item),
              ),
            );
          },
        ),
        GoRoute(
          path: register,
          pageBuilder: (context, state) => MaterialPage<bool>(
            key: state.pageKey,
            child: const RegisterScreen(),
          ),
        ),
        GoRoute(
          path: forgotPassword,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const ForgetPasswordScreen(),
          ),
        ),
        GoRoute(
          path: otpVerification,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: OneTimeVerificationScreen(
              email: _requiredStringExtra(state, 'email'),
            ),
          ),
        ),
        GoRoute(
          path: changePassword,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: ChangePasswordScreen(
              accessToken: _requiredStringExtra(state, 'accessToken'),
            ),
          ),
        ),
      ],
    );
  }

  static void goToHome(BuildContext context) {
    context.go(home);
  }

  static Future<void> openChatbot(BuildContext context) {
    return context.push<void>(chatbot);
  }

  static Future<void> openAddRentalItem(BuildContext context) {
    return context.push<void>(addRentalItem);
  }

  static Future<void> openItemDetail(
    BuildContext context, {
    required int itemId,
  }) {
    return context.push<void>('/items/$itemId');
  }

  static Future<bool?> openEditRentalItem(
    BuildContext context, {
    required ItemDetail item,
  }) {
    return context.push<bool>('/items/${item.id}/edit', extra: item);
  }

  static Future<void> openConversation(
    BuildContext context, {
    required ChatConversation conversation,
  }) {
    return context.push<void>(chatDetail, extra: conversation);
  }

  static void goToLogin(BuildContext context) {
    context.go(login);
  }

  static Future<bool?> openRegister(BuildContext context) {
    return context.push<bool>(register);
  }

  static Future<void> openForgotPassword(BuildContext context) {
    return context.push<void>(forgotPassword);
  }

  static Future<void> openOtpVerification(
    BuildContext context, {
    required String email,
  }) {
    return context.push<void>(otpVerification, extra: email);
  }

  static Future<void> openChangePassword(
    BuildContext context, {
    required String accessToken,
  }) {
    return context.push<void>(changePassword, extra: accessToken);
  }

  static void pop<T extends Object?>(BuildContext context, [T? result]) {
    context.pop<T>(result);
  }

  static String _requiredStringExtra(GoRouterState state, String argumentName) {
    final value = state.extra;
    if (value is String && value.isNotEmpty) {
      return value;
    }

    throw ArgumentError.value(
      value,
      argumentName,
      'Route ${state.uri.path} requires a non-empty String extra.',
    );
  }

  static ChatConversation _requiredConversationExtra(GoRouterState state) {
    final value = state.extra;
    if (value is ChatConversation) return value;

    throw ArgumentError.value(
      value,
      'conversation',
      'Route ${state.uri.path} requires a ChatConversation extra.',
    );
  }

  static int _requiredItemId(GoRouterState state) {
    final value = int.tryParse(state.pathParameters['itemId'] ?? '');
    if (value != null && value > 0) return value;

    throw ArgumentError.value(
      state.pathParameters['itemId'],
      'itemId',
      'Route ${state.uri.path} requires a positive item id.',
    );
  }

  static ItemDetail _requiredItemExtra(GoRouterState state) {
    final value = state.extra;
    if (value is ItemDetail) return value;

    throw ArgumentError.value(
      value,
      'item',
      'Route ${state.uri.path} requires an ItemDetail extra.',
    );
  }
}
