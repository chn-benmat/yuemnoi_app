import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/change_password.dart';
import '../../features/auth/presentation/pages/forget_password.dart';
import '../../features/auth/presentation/pages/login.dart';
import '../../features/auth/presentation/pages/one_time_verification.dart';
import '../../features/auth/presentation/pages/register.dart';
import '../../features/booking/presentation/pages/booking.dart';
import '../../features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import '../../features/chatbot/data/repositories/chatbot_repository_impl.dart';
import '../../features/chatbot/domain/usecases/send_chat_message_usecase.dart'
    as chatbot_uc;
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
import '../../features/profile/presentation/pages/contact_screen.dart';
import '../../features/profile/presentation/pages/faq_screen.dart';
import '../../features/profile/presentation/pages/my_items_screen.dart';
import '../../features/profile/presentation/pages/rental_status_screen.dart';
import '../../features/profile/presentation/pages/user_profile_view_screen.dart';
import '../../features/profile/presentation/pages/favorite_screen.dart';
import '../../features/profile/presentation/pages/rental_income_screen.dart';
import '../../features/profile/presentation/pages/rental_history_screen.dart';
import '../../features/profile/presentation/pages/terms_of_service_screen.dart';
import '../../features/profile/presentation/pages/privacy_policy_screen.dart';
import '../../features/profile/presentation/pages/setting_account_screen.dart';
import '../../features/profile/presentation/pages/edit_profile_screen.dart';
import '../../features/profile/presentation/pages/edit_contact_screen.dart';
import '../../features/profile/presentation/pages/change_account_screen.dart';
import '../../features/profile/presentation/pages/change_password_screen.dart';
abstract final class AppRoutes {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const login = '/login';
  static const home = '/home';
  static const chatbot = '/chatbot';
  static const chatDetail = '/chat/detail';
  static const register = '/register';

  static const forgotPassword = '/forgot-password';
  static const otpVerification = '/otp-verification';
  static const changePassword = '/change-password';
  static const booking = '/booking';
  static const bookingConfirmation = '/booking/confirm';
  static const addRentalItem = '/rental-items/add';
  static const myItems = '/profile/my-items';
  static const contact = '/profile/contact';
  static const faq = '/profile/faq';
  static const rentalStatus = '/profile/rental-status';
  static const favorite = '/profile/favorite';
  static const rentalIncome = '/profile/rental-income';
  static const rentalHistory = '/profile/rental-history';
  static const termsOfService = '/profile/terms-of-service';
  static const privacyPolicy = '/profile/privacy-policy';
  static const userProfileView = '/profile/view';
  static const settingAccount = '/setting/account';
  static const editProfile = '/setting/edit-profile';
  static const editContact = '/setting/edit-contact';
  static const changeAccount = '/setting/change-account';
  static const profileChangePassword = '/setting/change-password';
  static const itemDetail = '/items/:itemId';
  static const editRentalItem = '/items/:itemId/edit';

  static GoRouter? _currentRouter;
  static GoRouter? get router => _currentRouter;

  static GoRouter createRouter({
    String initialLocation = login,
    Object? initialExtra,
  }) {
    return _currentRouter = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: initialLocation,
      initialExtra: initialExtra,
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
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: chatbot,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (context) => ChatbotBloc(
                sendMessage: chatbot_uc.SendChatMessageUseCase(
                  ChatbotRepositoryImpl(
                    ChatbotRemoteDataSource(),
                  ),
                ),
              ),
              child: const ChatBotScreen(),
            ),
          ),
        ),
        GoRoute(
          path: chatDetail,
          pageBuilder: (context, state) => CupertinoPage<void>(
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
          path: myItems,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const MyItemsScreen(),
          ),
        ),
        GoRoute(
          path: contact,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const ContactScreen(),
          ),
        ),
        GoRoute(
          path: faq,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const FaqScreen(),
          ),
        ),
        GoRoute(
          path: rentalStatus,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const RentalStatusScreen(),
          ),
        ),
        GoRoute(
          path: favorite,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const FavoriteScreen(),
          ),
        ),
        GoRoute(
          path: rentalIncome,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const RentalIncomeScreen(),
          ),
        ),
        GoRoute(
          path: rentalHistory,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const RentalHistoryScreen(),
          ),
        ),
        GoRoute(
          path: termsOfService,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const TermsOfServiceScreen(),
          ),
        ),
        GoRoute(
          path: privacyPolicy,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const PrivacyPolicyScreen(),
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
            return MaterialPage<void>(
              key: state.pageKey,
              child: BlocProvider(
                create: (context) => ItemDetailBloc(
                  getItem: GetItemDetailUseCase(repository),
                  updateItem: UpdateItemUseCase(repository),
                ),
                child: EditItemScreen(item: item),
              ),
            );
          },
        ),
        GoRoute(
          path: register,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const RegisterScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: forgotPassword,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const ForgetPasswordScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: otpVerification,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: OneTimeVerificationScreen(
              email: _requiredStringExtra(state, 'email'),
            ),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: changePassword,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: ChangePasswordScreen(
              accessToken: _requiredStringExtra(state, 'accessToken'),
            ),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        ),
        GoRoute(
          path: userProfileView,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: UserProfileViewScreen(
              args: _requiredUserProfileArgs(state),
            ),
          ),
        ),
        GoRoute(
          path: settingAccount,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const SettingAccountScreen(),
          ),
        ),
        GoRoute(
          path: editProfile,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const EditProfileScreen(),
          ),
        ),
        GoRoute(
          path: editContact,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const EditContactScreen(),
          ),
        ),
        GoRoute(
          path: changeAccount,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const ChangeAccountScreen(),
          ),
        ),
        GoRoute(
          path: booking,
          pageBuilder: (context, state) {
            final data = state.extra is BookingRequestData
                ? state.extra as BookingRequestData
                : null;
            return MaterialPage<void>(
              key: state.pageKey,
              child: BookingRequestPage(initialData: data),
            );
          },
        ),
        GoRoute(
          path: bookingConfirmation,
          pageBuilder: (context, state) {
            final data = state.extra is BookingRequestData
                ? state.extra as BookingRequestData
                : null;
            return MaterialPage<void>(
              key: state.pageKey,
              child: BookingConfirmationPage(bookingData: data),
            );
          },
        ),
        GoRoute(
          path: profileChangePassword,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const ProfileChangePasswordScreen(),
          ),
        ),
      ],
    );
  }

  static void openLogin(BuildContext context) {
    context.go(login);
  }

  static void goToLogin(BuildContext context) {
    context.go(login);
  }

  static void openHome(BuildContext context) {
    context.go(home);
  }

  static void goToHome(BuildContext context) {
    context.go(home);
  }

  static Future<void> openChatbot(BuildContext context) {
    return context.push<void>(chatbot);
  }

  static Future<void> openChatDetail(
    BuildContext? context, {
    required ChatConversation conversation,
  }) {
    if (_currentRouter != null) {
      return _currentRouter!.push<void>(chatDetail, extra: conversation);
    }
    final targetContext = navigatorKey.currentContext ?? context;
    if (targetContext != null) {
      return targetContext.push<void>(chatDetail, extra: conversation);
    }
    return Future.value();
  }

  static Future<void> openConversation(
    BuildContext? context, {
    required ChatConversation conversation,
  }) {
    return openChatDetail(context, conversation: conversation);
  }



  static Future<void> openBooking(
    BuildContext context, {
    BookingRequestData? initialData,
    int? itemId,
  }) {
    return context.push<void>(booking, extra: initialData);
  }

  static Future<void> openBookingConfirmation(
    BuildContext context, {
    BookingRequestData? bookingData,
  }) {
    return context.push<void>(bookingConfirmation, extra: bookingData);
  }

  static Future<void> openAddRentalItem(BuildContext context) {

    return context.push<void>(addRentalItem);
  }

  static Future<void> openMyItems(BuildContext context) {
    return context.push<void>(myItems);
  }

  static Future<void> openContact(BuildContext context) {
    return context.push<void>(contact);
  }

  static Future<void> openFaq(BuildContext context) {
    return context.push<void>(faq);
  }

  static Future<void> openRentalStatus(BuildContext context) {
    return context.push<void>(rentalStatus);
  }

  static Future<void> openFavorite(BuildContext context) {
    return context.push<void>(favorite);
  }

  static Future<void> openRentalIncome(BuildContext context) {
    return context.push<void>(rentalIncome);
  }

  static Future<void> openRentalHistory(BuildContext context) {
    return context.push<void>(rentalHistory);
  }

  static Future<void> openTermsOfService(BuildContext context) {
    return context.push<void>(termsOfService);
  }

  static Future<void> openPrivacyPolicy(BuildContext context) {
    return context.push<void>(privacyPolicy);
  }

  static Future<void> openUserProfile(
    BuildContext context, {
    required UserProfileViewArgs args,
  }) {
    return context.push<void>(userProfileView, extra: args);
  }

  static Future<void> openSettingAccount(BuildContext context) {
    return context.push<void>(settingAccount);
  }

  static Future<void> openEditProfile(BuildContext context) {
    return context.push<void>(editProfile);
  }

  static Future<void> openEditContact(BuildContext context) {
    return context.push<void>(editContact);
  }

  static Future<void> openChangeAccount(BuildContext context) {
    return context.push<void>(changeAccount);
  }

  static Future<void> openProfileChangePassword(BuildContext context) {
    return context.push<void>(profileChangePassword);
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

  static Future<void> openRegister(BuildContext context) {
    return context.push<void>(register);
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
    try {
      if (context.canPop()) {
        context.pop<T>(result);
        return;
      }
    } catch (_) {}
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop(result);
      return;
    }
    // Fallback if no history to pop (e.g. launched directly from notification / pushReplacement)
    try {
      context.go(home);
    } catch (_) {}
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

    if (value is Map<String, dynamic> && value['conversation'] is ChatConversation) {
      return value['conversation'] as ChatConversation;
    }

    throw ArgumentError.value(
      value,
      'conversation',
      'Route ${state.uri.path} requires a ChatConversation extra.',
    );
  }

  static UserProfileViewArgs _requiredUserProfileArgs(GoRouterState state) {
    final value = state.extra;
    if (value is UserProfileViewArgs) return value;
    // Fallback — ป้องกัน crash กรณีไม่มี extra
    return const UserProfileViewArgs(userId: 'unknown', displayName: 'ผู้ใช้');
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
