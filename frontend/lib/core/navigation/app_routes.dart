import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/change_password.dart';
import '../../features/auth/presentation/pages/forget_password.dart';
import '../../features/auth/presentation/pages/login.dart';
import '../../features/auth/presentation/pages/one_time_verification.dart';
import '../../features/auth/presentation/pages/register.dart';
import '../utils/auth_guard.dart';
import '../../features/booking/presentation/pages/booking.dart';
import '../../features/booking/presentation/pages/location_picker_map_page.dart';
import '../../features/booking/data/datasources/rental_request_remote_data_source.dart';
import '../../features/booking/data/repositories/rental_request_repository_impl.dart';
import '../../features/booking/domain/usecases/submit_rental_request_usecase.dart';
import '../../features/booking/presentation/bloc/rental_request_cubit.dart';
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
import '../../features/home/domain/entities/feed_category.dart';
import '../../features/home/domain/entities/feed_item.dart';
import '../../features/home/presentation/pages/equipment_search_screen.dart';
import '../../features/home/presentation/pages/home.dart';
import '../../features/rental_item/data/datasources/rental_item_remote_data_source.dart';
import '../../features/rental_item/data/repositories/rental_item_repository_impl.dart';
import '../../features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import '../../features/rental_item/presentation/bloc/rental_item_bloc.dart';
import '../../features/rental_item/presentation/pages/add_rental_item.dart';
import '../../features/profile/presentation/pages/account/change_account_screen.dart';
import '../../features/profile/presentation/pages/account/change_password_screen.dart';
import '../../features/profile/presentation/pages/account/edit_contact_screen.dart';
import '../../features/profile/presentation/pages/account/edit_profile_screen.dart';
import '../../features/profile/presentation/pages/account/setting_account_screen.dart';
import '../../features/profile/presentation/pages/items/favorite_screen.dart';
import '../../features/profile/presentation/pages/items/my_items_screen.dart';
import '../../features/profile/presentation/pages/legal/privacy_policy_screen.dart';
import '../../features/profile/presentation/pages/legal/terms_of_service_screen.dart';
import '../../features/profile/presentation/pages/profile/user_profile_view_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_history_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_income_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_status_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import '../../features/profile/presentation/pages/rentals/rental_payment_success_screen.dart';
import '../../features/profile/presentation/pages/support/contact_screen.dart';
import '../../features/profile/presentation/pages/support/faq_screen.dart';
import '../../features/wallet/presentation/pages/wallet.dart';
import '../../features/wallet/presentation/pages/wallet_payment_screen.dart';
import '../../features/wallet/presentation/pages/wallet_success_screen.dart';
import '../../features/notification/presentation/pages/page.dart';
import '../../features/review/presentation/pages/rental_review_screen.dart';
import '../../features/rental_return/presentation/pages/rental_return_page.dart';

abstract final class AppRoutes {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const login = '/login';
  static const home = '/home';
  static const search = '/search';
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
  static const rentalTrackingMap = '/rental-tracking-map';
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
  static const wallet = '/wallet';
  static const walletPayment = '/wallet/payment';
  static const walletSuccess = '/wallet/success';
  static const paymentReturn = '/payments/:rentalId';
  static const rentalReturn = '/rental/return/:rentalId';
  static const rentalReturnDemo = '/rental/return';
  static const rentalPaymentSuccess = '/rentals/payment-success';
  static const review = '/review';
  static const notification = '/notifications';

  static GoRouter? _currentRouter;
  static GoRouter? get router => _currentRouter;

  static GoRouter createRouter({
    String initialLocation = home,
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
          pageBuilder: (context, state) {
            final initialIndex = (state.extra as int?) ?? 0;
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: HomeScreen(
                key: ValueKey('home_screen_$initialIndex'),
                initialIndex: initialIndex,
              ),
              transitionDuration: const Duration(milliseconds: 600),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            );
          },
        ),
        GoRoute(
          path: search,
          pageBuilder: (context, state) {
            final extra = state.extra;
            List<FeedItem>? curatedItems;
            String? initialQuery;
            List<FeedCategory>? categories;
            if (extra is List<FeedItem>) {
              curatedItems = extra;
            } else if (extra is Map<String, dynamic>) {
              curatedItems = extra['curatedItems'] as List<FeedItem>?;
              initialQuery = extra['query'] as String?;
              categories = extra['categories'] as List<FeedCategory>?;
            }
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: EquipmentSearchScreen(
                initialCuratedItems: curatedItems,
                initialQuery: initialQuery,
                initialCategories: categories,
              ),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            );
          },
        ),
        GoRoute(
          path: chatbot,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (context) => ChatbotBloc(
                sendMessage: chatbot_uc.SendChatMessageUseCase(
                  ChatbotRepositoryImpl(ChatbotRemoteDataSource()),
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
          pageBuilder: (context, state) =>
              MaterialPage<void>(key: state.pageKey, child: const FaqScreen()),
        ),
        GoRoute(
          path: rentalStatus,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const RentalStatusScreen(),
          ),
        ),
        GoRoute(
          path: rentalTrackingMap,
          pageBuilder: (context, state) {
            final extra = state.extra;
            if (extra is BookingRequestData) {
              return MaterialPage<void>(
                key: state.pageKey,
                child: RentalTrackingMapPage(bookingData: extra),
              );
            } else if (extra is Map<String, dynamic>) {
              return MaterialPage<void>(
                key: state.pageKey,
                child: RentalTrackingMapPage(
                  bookingData: extra['bookingData'] as BookingRequestData?,
                  itemTitle: extra['itemTitle'] as String?,
                  itemImageUrl: extra['itemImageUrl'] as String?,
                  pickupLocation: extra['pickupLocation'] as String?,
                  pickupNote: extra['pickupNote'] as String?,
                  destinationLat: (extra['destinationLat'] as num?)?.toDouble(),
                  destinationLng: (extra['destinationLng'] as num?)?.toDouble(),
                  ownerName: extra['ownerName'] as String?,
                  ownerPhone: extra['ownerPhone'] as String?,
                  periodText: extra['periodText'] as String?,
                  totalPrice: (extra['totalPrice'] as num?)?.toDouble(),
                  conversationId: extra['conversationId'] as String?,
                  statusCode: extra['statusCode'] as String?,
                  bookingId: (extra['bookingId'] as num?)?.toInt(),
                ),
              );
            }
            return MaterialPage<void>(
              key: state.pageKey,
              child: const RentalTrackingMapPage(),
            );
          },
        ),
        GoRoute(
          path: rentalReturn,
          pageBuilder: (context, state) {
            final idStr = state.pathParameters['rentalId'];
            final rentalId = idStr != null ? int.tryParse(idStr) : null;
            final isLender = state.extra as bool?;
            return MaterialPage<void>(
              key: state.pageKey,
              child: RentalReturnPage(rentalId: rentalId, isLender: isLender),
            );
          },
        ),
        GoRoute(
          path: rentalReturnDemo,
          pageBuilder: (context, state) {
            final isLender = state.extra as bool?;
            return MaterialPage<void>(
              key: state.pageKey,
              child: RentalReturnPage(isLender: isLender),
            );
          },
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
            child: UserProfileViewScreen(args: _requiredUserProfileArgs(state)),
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
            if (state.extra is BookingRequestData) {
              return MaterialPage<void>(
                key: state.pageKey,
                child: BookingRequestPage(
                  initialData: state.extra as BookingRequestData,
                ),
              );
            }
            if (state.extra is Map<String, dynamic>) {
              final map = state.extra as Map<String, dynamic>;
              return MaterialPage<void>(
                key: state.pageKey,
                child: BookingRequestPage(
                  initialData: map['initialData'] as BookingRequestData?,
                  itemId: map['itemId'] as int?,
                  isEditMode: map['isEditMode'] as bool? ?? false,
                ),
              );
            }
            return MaterialPage<void>(
              key: state.pageKey,
              child: const BookingRequestPage(),
            );
          },
        ),
        GoRoute(
          path: bookingConfirmation,
          pageBuilder: (context, state) {
            final data = state.extra is BookingRequestData
                ? state.extra as BookingRequestData
                : null;
            final repository = RentalRequestRepositoryImpl(
              RentalRequestRemoteDataSource(),
            );
            return MaterialPage<void>(
              key: state.pageKey,
              child: BlocProvider(
                create: (context) => RentalRequestCubit(
                  submitRentalRequest: SubmitRentalRequestUseCase(repository),
                  repository: repository,
                ),
                child: BookingConfirmationPage(bookingData: data),
              ),
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
        GoRoute(
          path: wallet,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const WalletScreen(),
          ),
        ),
        GoRoute(
          path: walletPayment,
          pageBuilder: (context, state) {
            final amount = (state.extra as num?)?.toDouble() ?? 0.0;
            return MaterialPage<void>(
              key: state.pageKey,
              child: WalletPaymentScreen(amount: amount),
            );
          },
        ),
        GoRoute(
          path: walletSuccess,
          pageBuilder: (context, state) {
            final amount = (state.extra as num?)?.toDouble() ?? 0.0;
            return MaterialPage<void>(
              key: state.pageKey,
              child: WalletSuccessScreen(amount: amount),
            );
          },
        ),
        GoRoute(
          path: rentalPaymentSuccess,
          pageBuilder: (context, state) => const MaterialPage<void>(
            child: RentalPaymentSuccessScreen(),
          ),
        ),
        GoRoute(
          path: review,
          pageBuilder: (context, state) => const MaterialPage<void>(
            child: RentalReviewScreen(),
          ),
        ),
        GoRoute(
          path: rentalReturn,
          pageBuilder: (context, state) {
            final rentalId = int.tryParse(state.pathParameters['rentalId'] ?? '');
            final isLender = state.extra as bool?;
            return MaterialPage<void>(
              key: state.pageKey,
              child: RentalReturnPage(rentalId: rentalId, isLender: isLender),
            );
          },
        ),
        GoRoute(
          path: rentalReturnDemo,
          pageBuilder: (context, state) {
            final isLender = state.extra as bool?;
            return MaterialPage<void>(
              key: state.pageKey,
              child: RentalReturnPage(isLender: isLender),
            );
          },
        ),
        GoRoute(
          path: notification,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const NotificationPage(),
          ),
        ),
      ],
    );
  }

  static void openLogin(BuildContext context) {
    context.go(login);
  }

  static Future<bool?> pushLogin(BuildContext context) {
    return context.push<bool>(login);
  }

  static void goToLogin(BuildContext context) {
    context.go(login);
  }

  static void openHome(BuildContext context, {int initialIndex = 0}) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    context.go(home, extra: initialIndex);
  }

  static void goToHome(BuildContext context, {int initialIndex = 0}) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    context.go(home, extra: initialIndex);
  }

  static void openNotification(BuildContext context) {
    goToHome(context, initialIndex: 2);
  }

  static void goToNotification(BuildContext context) {
    goToHome(context, initialIndex: 2);
  }

  static void openProfile(BuildContext context) {
    goToHome(context, initialIndex: 4);
  }

  static void goToProfile(BuildContext context) {
    goToHome(context, initialIndex: 4);
  }

  static Future<void> openChatbot(BuildContext context) {
    return context.push<void>(chatbot);
  }

  static Future<void> openReview(BuildContext context) {
    return context.push<void>(review);
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
    bool isEditMode = false,
  }) {
    if (isEditMode || itemId != null) {
      return context.push<void>(
        booking,
        extra: {
          'initialData': initialData,
          'itemId': itemId,
          'isEditMode': isEditMode,
        },
      );
    }
    return context.push<void>(booking, extra: initialData);
  }

  static Future<bool?> openBookingConfirmation(
    BuildContext context, {
    BookingRequestData? bookingData,
    bool isDetailView = false,
  }) {
    if (isDetailView) {
      return Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: '/booking-detail-view'),
          builder: (_) => BookingConfirmationPage(
            bookingData: bookingData,
            isDetailView: true,
          ),
        ),
      );
    }
    return context.push<bool>(bookingConfirmation, extra: bookingData);
  }

  static Future<LocationPickerResult?> openLocationPicker(
    BuildContext context, {
    String? initialLocationName,
    String? initialNote,
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerMapPage(
          initialLocationName: initialLocationName,
          initialNote: initialNote,
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
        ),
      ),
    );
  }

  static Future<void> openAddRentalItem(BuildContext context) async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อปล่อยเช่าอุปกรณ์',
      message:
          'กรุณาเข้าสู่ระบบหรือสมัครสมาชิกก่อนลงประกาศปล่อยเช่าอุปกรณ์ของคุณ เพื่อความปลอดภัยและการติดต่อกับผู้เช่า',
    );
    if (!authed || !context.mounted) return;
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

  static Future<void> openRentalTrackingMap(
    BuildContext context, {
    BookingRequestData? bookingData,
    Map<String, dynamic>? trackingArgs,
    bool? isOwner,
  }) {
    final page = RentalTrackingMapPage(
      bookingData: bookingData ??
          (trackingArgs?['bookingData'] as BookingRequestData?),
      itemTitle: trackingArgs?['itemTitle'] as String?,
      itemImageUrl: trackingArgs?['itemImageUrl'] as String?,
      pickupLocation: trackingArgs?['pickupLocation'] as String?,
      pickupNote: trackingArgs?['pickupNote'] as String?,
      destinationLat: (trackingArgs?['destinationLat'] as num?)?.toDouble(),
      destinationLng: (trackingArgs?['destinationLng'] as num?)?.toDouble(),
      ownerName: trackingArgs?['ownerName'] as String?,
      ownerPhone: trackingArgs?['ownerPhone'] as String?,
      periodText: trackingArgs?['periodText'] as String?,
      totalPrice: (trackingArgs?['totalPrice'] as num?)?.toDouble(),
      conversationId: trackingArgs?['conversationId'] as String?,
      statusCode: trackingArgs?['statusCode'] as String?,
      bookingId: (trackingArgs?['bookingId'] as num?)?.toInt(),
      isOwner: isOwner ?? (trackingArgs?['isOwner'] as bool?),
    );

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: rentalTrackingMap),
        builder: (_) => page,
      ),
    );
  }

  static Future<void> openFavorite(BuildContext context) {
    try {
      return context.push<void>(favorite);
    } catch (_) {
      return Future.value();
    }
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

  static Future<void> openSearch(
    BuildContext context, {
    List<FeedItem>? curatedItems,
    String? initialQuery,
    List<FeedCategory>? categories,
  }) {
    try {
      return context.push<void>(
        search,
        extra: {
          'curatedItems': ?curatedItems,
          'query': ?initialQuery,
          'categories': ?categories,
        },
      );
    } catch (_) {
      return Future.value();
    }
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

  static Future<void> openWallet(BuildContext context) {
    return context.push<void>(wallet);
  }

  static Future<void> openWalletPayment(
    BuildContext context, {
    required double amount,
  }) {
    return context.push<void>(walletPayment, extra: amount);
  }

  static Future<void> openWalletSuccess(
    BuildContext context, {
    double amount = 0,
  }) {
    return context.push<void>(walletSuccess, extra: amount);
  }

  static Future<void> openRentalReturn(
    BuildContext context, {
    int? rentalId,
    bool? isLender,
  }) {
    final route = rentalId != null ? '/rental/return/$rentalId' : rentalReturnDemo;
    return context.push<void>(route, extra: isLender);
  }

  static Future<void> openRentalPaymentSuccess(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: rentalPaymentSuccess),
        builder: (_) => const RentalPaymentSuccessScreen(),
      ),
    );
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

    if (value is Map<String, dynamic> &&
        value['conversation'] is ChatConversation) {
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
