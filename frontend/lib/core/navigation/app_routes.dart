import 'package:frontend/core/widgets/app_popup.dart';
import '../../features/rental_item/domain/entities/rental_item.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'item_detail_route_args.dart';
import '../../features/identity/data/identity_api_repository.dart';
import '../../features/identity/data/identity_consent_preferences.dart';
import '../../features/identity/domain/identity_repository.dart';
import '../../features/identity/domain/rental_verification.dart';
import '../../features/identity/presentation/identity_account_cubit.dart';
import '../../features/identity/presentation/pages/identity_account_page.dart';
import '../../features/identity/presentation/widgets/rental_verification_dialog.dart';

import '../../features/auth/presentation/pages/change_password.dart';
import '../../features/auth/presentation/pages/forget_password.dart';
import '../../features/auth/presentation/pages/login.dart';
import '../../features/auth/presentation/pages/one_time_verification.dart';
import '../../features/auth/presentation/pages/register.dart';
import '../models/pickup_location.dart';
import '../network/api_client.dart';
import '../network/auth_session.dart';
import '../utils/auth_guard.dart';
import '../../features/booking/presentation/pages/booking.dart';
import '../../features/booking/presentation/pages/pickup_details_page.dart';
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
import '../../features/item_detail/data/datasources/related_items_remote_data_source.dart';
import '../../features/item_detail/data/repositories/related_items_repository_impl.dart';
import '../../features/item_detail/domain/entities/item_detail.dart';
import '../../features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import '../../features/item_detail/domain/usecases/get_related_items_usecase.dart';
import '../../features/item_detail/domain/usecases/update_item_usecase.dart';
import '../../features/item_detail/domain/usecases/manage_owner_item_usecase.dart';
import '../../features/item_detail/presentation/bloc/item_detail_bloc.dart';
import '../../features/item_detail/presentation/bloc/item_detail_event.dart';
import '../../features/item_detail/presentation/pages/edit_item.dart';
import '../../features/item_detail/presentation/pages/item_detail.dart';
import '../../features/item_detail/presentation/pages/item_auto_reply_settings.dart';
import '../../features/home/domain/entities/feed_category.dart';
import '../../features/home/domain/entities/feed_item.dart';
import '../../features/home/presentation/pages/equipment_search_screen.dart';
import '../../features/home/presentation/pages/home.dart';
import '../../features/rental_item/data/datasources/rental_item_remote_data_source.dart';
import '../../features/rental_item/data/repositories/rental_item_repository_impl.dart';
import '../../features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import '../../features/rental_item/presentation/bloc/rental_item_bloc.dart';
import '../../features/rental_item/presentation/pages/add_rental_item.dart';
import '../../features/profile/data/repositories/promptpay_account_repository.dart';
import '../../features/profile/presentation/bloc/promptpay_account_cubit.dart';
import '../../features/profile/presentation/pages/account/change_account_screen.dart';
import '../../features/profile/presentation/pages/account/change_password_screen.dart';
import '../../features/profile/presentation/pages/account/edit_contact_screen.dart';
import '../../features/profile/presentation/pages/account/edit_profile_screen.dart';
import '../../features/profile/presentation/pages/account/promptpay_account_screen.dart';
import '../../features/profile/presentation/pages/account/setting_account_screen.dart';
import '../../features/profile/presentation/pages/items/favorite_screen.dart';
import '../../features/profile/presentation/pages/items/my_items_screen.dart';
import '../../features/profile/presentation/pages/legal/privacy_policy_screen.dart';
import '../../features/profile/presentation/pages/legal/terms_of_service_screen.dart';
import '../../features/profile/presentation/pages/profile/user_profile_view_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_history_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_income_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_status_screen.dart';
import '../../features/profile/presentation/pages/rentals/rental_handover_page.dart';
import '../../features/profile/presentation/pages/support/contact_screen.dart';
import '../../features/profile/presentation/pages/support/faq_screen.dart';
import '../../features/wallet/presentation/pages/wallet.dart';
import '../../features/wallet/presentation/pages/wallet_payment_screen.dart';
import '../../features/wallet/presentation/pages/wallet_success_screen.dart';
import '../../features/review/presentation/pages/rental_review_screen.dart';
import '../../features/rental_return/presentation/pages/rental_return_page.dart';
import '../../features/notification/presentation/pages/page.dart';

abstract final class AppRoutes {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const login = '/login';
  static const identity = '/profile/identity';
  static const home = '/home';
  static const recommendationLocationOnboarding =
      '/recommendation-location-onboarding';
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
  static const rentalHandover = '/rental-tracking-map';
  static const favorite = '/profile/favorite';
  static const rentalIncome = '/profile/rental-income';
  static const rentalHistory = '/profile/rental-history';
  static const termsOfService = '/profile/terms-of-service';
  static const privacyPolicy = '/profile/privacy-policy';
  static const userProfileView = '/profile/view';
  static const settingAccount = '/setting/account';
  static const editProfile = '/setting/edit-profile';
  static const editContact = '/setting/edit-contact';
  static const identityAccount = '/setting/identity';
  static const promptPayAccount = '/setting/promptpay';
  static const changeAccount = '/setting/change-account';
  static const profileChangePassword = '/setting/change-password';
  static const itemDetail = '/items/:itemId';
  static const editRentalItem = '/items/:itemId/edit';
  static const itemAutoReply = '/items/:itemId/auto-reply';
  static const wallet = '/wallet';
  static const walletPayment = '/wallet/payment';
  static const walletSuccess = '/wallet/success';
  static const paymentReturn = '/payments/:rentalId';
  static const rentalReturn = '/rental/return/:rentalId';
  static const rentalReturnDemo = '/rental/return';
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
      overridePlatformDefaultLocation: initialLocation == login,
      initialExtra: initialExtra,
      routes: [
        GoRoute(
          path: recommendationLocationOnboarding,
          redirect: (_, _) => home,
        ),
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
            final extra = state.extra;
            final initialIndex = extra is int
                ? extra
                : extra is Map
                ? (extra['initialIndex'] as int? ?? 0)
                : 0;
            final message = extra is Map ? extra['message'] as String? : null;
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: HomeScreen(
                key: ValueKey(
                  'home_screen_${initialIndex}_${extra is Map ? extra['navigationId'] : ''}',
                ),
                initialIndex: initialIndex,
                initialMessage: message,
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
            String? initialCategoryId;
            int? minPrice;
            int? maxPrice;
            double? minRating;
            List<FeedCategory>? categories;
            ValueChanged<String>? onCategoryInterest;
            if (extra is List<FeedItem>) {
              curatedItems = extra;
            } else if (extra is Map<String, dynamic>) {
              curatedItems = extra['curatedItems'] as List<FeedItem>?;
              initialQuery = extra['query'] as String?;
              initialCategoryId = extra['categoryId'] as String?;
              minPrice = extra['minPrice'] as int?;
              maxPrice = extra['maxPrice'] as int?;
              minRating = extra['minRating'] as double?;
              categories = extra['categories'] as List<FeedCategory>?;
              onCategoryInterest =
                  extra['onCategoryInterest'] as ValueChanged<String>?;
            }
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: EquipmentSearchScreen(
                initialCuratedItems: curatedItems,
                initialQuery: initialQuery,
                initialCategoryId: initialCategoryId,
                initialMinPrice: minPrice,
                initialMaxPrice: maxPrice,
                initialMinRating: minRating,
                initialCategories: categories,
                onCategoryInterest: onCategoryInterest,
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
            name: chatDetail,
            child: ChatDetailScreen(
              conversation: _requiredConversationExtra(state),
              initialMessageId: switch (state.extra) {
                {'initialMessageId': final String id} => id,
                _ => null,
              },
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
            child: RentalStatusScreen(
              isLender: state.uri.queryParameters['role'] == 'lender',
              initialBookingId: int.tryParse(
                state.uri.queryParameters['booking_id'] ?? '',
              ),
            ),
          ),
        ),
        GoRoute(
          path: rentalHandover,
          pageBuilder: (context, state) {
            final extra = state.extra;
            if (extra is BookingRequestData) {
              return MaterialPage<void>(
                key: state.pageKey,
                child: RentalHandoverPage(
                  bookingData: extra,
                  requireBookingId: true,
                ),
              );
            } else if (extra is Map<String, dynamic>) {
              return MaterialPage<void>(
                key: state.pageKey,
                child: RentalHandoverPage(
                  bookingData: extra['bookingData'] as BookingRequestData?,
                  itemTitle: extra['itemTitle'] as String?,
                  itemImageUrl: extra['itemImageUrl'] as String?,
                  pickupLocation: extra['pickupLocation'] as String?,
                  pickupAddress: extra['pickupAddress'] as String?,
                  pickupLatitude: (extra['pickupLatitude'] as num?)?.toDouble(),
                  pickupLongitude: (extra['pickupLongitude'] as num?)
                      ?.toDouble(),
                  ownerName: extra['ownerName'] as String?,
                  ownerPhone: extra['ownerPhone'] as String?,
                  periodText: extra['periodText'] as String?,
                  totalPrice: (extra['totalPrice'] as num?)?.toDouble(),
                  conversationId: extra['conversationId'] as String?,
                  statusCode: extra['statusCode'] as String?,
                  bookingId: (extra['bookingId'] as num?)?.toInt(),
                  startDate: extra['startDate'] is DateTime
                      ? extra['startDate'] as DateTime
                      : DateTime.tryParse(extra['startDate']?.toString() ?? ''),
                  isOwner: extra['isOwner'] as bool?,
                  requireBookingId: true,
                ),
              );
            }
            return MaterialPage<void>(
              key: state.pageKey,
              child: const RentalHandoverPage(requireBookingId: true),
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
                  manageItem: ManageOwnerItemUseCase(repository),
                  getRelatedItems: GetRelatedItemsUseCase(
                    RelatedItemsRepositoryImpl(RelatedItemsRemoteDataSource()),
                  ),
                )..add(ItemDetailRequested(itemId)),
                child: ItemDetailScreen(
                  itemId: itemId,
                  ownerLoadingLayout:
                      state.extra is ItemDetailRouteArgs &&
                      (state.extra as ItemDetailRouteArgs).ownerLoadingLayout,
                ),
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
                  manageItem: ManageOwnerItemUseCase(repository),
                ),
                child: EditItemScreen(item: item),
              ),
            );
          },
        ),
        GoRoute(
          path: itemAutoReply,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: ItemAutoReplyScreen(item: _requiredItemExtra(state)),
          ),
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
          path: identityAccount,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (_) => IdentityAccountCubit(
                IdentityApiRepository(),
                consentStore: IdentityConsentPreferences(AuthSession.userId),
              ),
              child: const IdentityAccountPage(),
            ),
          ),
        ),
        GoRoute(
          path: promptPayAccount,
          redirect: (_, _) => AuthGuard.isAuthenticated ? null : login,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: BlocProvider(
              create: (_) =>
                  PromptPayAccountCubit(PromptPayAccountRepository())..load(),
              child: const PromptPayAccountScreen(),
            ),
          ),
        ),
        GoRoute(
          path: changeAccount,
          redirect: (_, _) => AuthGuard.isAuthenticated ? null : login,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: const ChangeAccountScreen(),
          ),
        ),
        GoRoute(
          path: booking,
          pageBuilder: (context, state) {
            final page = switch (state.extra) {
              final BookingRequestData data => BookingRequestPage(
                initialData: data,
              ),
              final Map<String, dynamic> map => BookingRequestPage(
                initialData: map['initialData'] as BookingRequestData?,
                itemId: map['itemId'] as int?,
                isEditMode: map['isEditMode'] as bool? ?? false,
                originalQueueOfferMessage:
                    map['originalQueueOfferMessage'] as String?,
                onSendRequest:
                    map['onSendRequest'] as ValueChanged<BookingRequestData>?,
              ),
              _ => const BookingRequestPage(),
            };
            return MaterialPage<void>(
              key: state.pageKey,
              child: page.initialData?.isCustomerRequest == true
                  ? BlocProvider(
                      create: (_) {
                        final repository = RentalRequestRepositoryImpl(
                          RentalRequestRemoteDataSource(),
                        );
                        return RentalRequestCubit(
                          submitRentalRequest: SubmitRentalRequestUseCase(
                            repository,
                          ),
                          repository: repository,
                        );
                      },
                      child: page,
                    )
                  : page,
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
          path: review,
          pageBuilder: (context, state) {
            final extra = state.extra;
            final args = extra is Map ? extra : const <String, dynamic>{};
            final initialRating = args['initialRating'];
            return MaterialPage<void>(
              child: RentalReviewScreen(
                bookingId: args['bookingId'] is num
                    ? (args['bookingId'] as num).toInt()
                    : null,
                itemName: args['itemName'] as String? ?? 'อุปกรณ์ที่เช่า',
                itemId: args['itemId'] is num
                    ? (args['itemId'] as num).toInt()
                    : null,
                ownerName: args['ownerName'] as String? ?? 'ผู้ปล่อยเช่า',
                ownerId: args['ownerId'] as String?,
                ownerAvatarUrl: args['ownerAvatarUrl'] as String?,
                itemImageUrl: args['itemImageUrl'] as String?,
                initialRating: initialRating is int ? initialRating : 0,
              ),
            );
          },
        ),
        GoRoute(
          path: rentalReturn,
          pageBuilder: (context, state) {
            final rentalId = int.tryParse(
              state.pathParameters['rentalId'] ?? '',
            );
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

  static void goToHomeAfterRental(BuildContext context) {
    GoRouter.of(context).go(home, extra: 0);
  }

  static void openProfile(BuildContext context) {
    goToHome(context, initialIndex: 3);
  }

  static void goToProfile(BuildContext context) {
    goToHome(context, initialIndex: 3);
  }

  static Future<void> openChatbot(BuildContext context) {
    return context.push<void>(chatbot);
  }

  static Future<void> openReview(
    BuildContext context, {
    String? itemName,
    int? itemId,
    int? bookingId,
    String? ownerName,
    String? ownerId,
    String? ownerAvatarUrl,
    String? itemImageUrl,
    int? initialRating,
  }) {
    return context.push<void>(
      review,
      extra: {
        if (itemName != null) 'itemName': itemName,
        if (itemId != null) 'itemId': itemId,
        if (bookingId != null) 'bookingId': bookingId,
        if (ownerName != null) 'ownerName': ownerName,
        if (ownerId != null) 'ownerId': ownerId,
        if (ownerAvatarUrl != null) 'ownerAvatarUrl': ownerAvatarUrl,
        if (itemImageUrl != null) 'itemImageUrl': itemImageUrl,
        'initialRating': ?initialRating,
      },
    );
  }

  static Future<void> openChatDetail(
    BuildContext? context, {
    required ChatConversation conversation,
    String? initialMessageId,
  }) {
    final extra = initialMessageId == null
        ? conversation
        : {'conversation': conversation, 'initialMessageId': initialMessageId};
    if (_currentRouter != null) {
      return _currentRouter!.push<void>(chatDetail, extra: extra);
    }
    final targetContext = navigatorKey.currentContext ?? context;
    if (targetContext != null) {
      return targetContext.push<void>(chatDetail, extra: extra);
    }
    return Future.value();
  }

  static Future<void> openConversation(
    BuildContext? context, {
    required ChatConversation conversation,
    String? initialMessageId,
  }) {
    return openChatDetail(
      context,
      conversation: conversation,
      initialMessageId: initialMessageId,
    );
  }

  static void returnToChatAfterPickup(
    BuildContext context, {
    required bool returnToPreviousChat,
    ChatConversation? conversation,
  }) {
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    if (navigator.canPop()) {
      navigator.pop();
      if (returnToPreviousChat) return;
      if (conversation != null) {
        router?.push<void>(chatDetail, extra: conversation);
        return;
      }
    }
    if (conversation == null) {
      router?.go(home, extra: 1);
    } else {
      router?.go(chatDetail, extra: conversation);
    }
  }

  static Future<void> openBooking(
    BuildContext context, {
    BookingRequestData? initialData,
    int? itemId,
    bool isEditMode = false,
    ValueChanged<BookingRequestData>? onSendRequest,
    String? originalQueueOfferMessage,
  }) {
    if (isEditMode || itemId != null || onSendRequest != null) {
      return context.push<void>(
        booking,
        extra: {
          'initialData': initialData,
          'itemId': itemId,
          'isEditMode': isEditMode,
          'onSendRequest': onSendRequest,
          'originalQueueOfferMessage': originalQueueOfferMessage,
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

  static Future<PickupLocation?> openPickupDetails(
    BuildContext context, {
    PickupLocation? initialLocation,
    Future<Position?>? initialDevicePosition,
  }) {
    return Navigator.of(context).push<PickupLocation>(
      MaterialPageRoute(
        builder: (_) => PickupDetailsPage(
          initialLocation: initialLocation,
          initialDevicePosition: initialDevicePosition,
        ),
      ),
    );
  }

  static Future<void> openAddRentalItem(
    BuildContext context, {
    IdentityRepository? identityRepository,
  }) async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อปล่อยเช่าอุปกรณ์',
      message:
          'กรุณาเข้าสู่ระบบหรือสมัครสมาชิกก่อนลงประกาศปล่อยเช่าอุปกรณ์ของคุณ เพื่อความปลอดภัยและการติดต่อกับผู้เช่า',
    );
    if (!authed || !context.mounted) return;
    final repository =
        identityRepository ?? IdentityApiRepository(client: DioApiClient());
    final IdentityStatus status;
    try {
      status = await repository.status();
    } on IdentityFailure catch (e) {
      if (context.mounted) {
        showAppPopup(context, content: Text(e.message));
      }
      return;
    } finally {
      if (identityRepository == null) repository.close();
    }
    if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (status.restricted) {
      showAppPopup(
        context,
        content: const Text('บัญชีนี้ถูกจำกัดการทำธุรกรรมใหม่'),
      );
      return;
    }
    final verification = status.rentalVerification;
    if (verification == null) {
      showAppPopup(
        context,
        content: const Text('ระบบตรวจสอบข้อมูลยังไม่พร้อม กรุณาลองใหม่'),
      );
      return;
    }
    if (!verification.isComplete) {
      return openRentalVerification(
        context,
        verification,
        action: 'เพิ่มสินค้า',
      );
    }
    return context.push<void>(addRentalItem);
  }

  static Future<void> openRentalVerification(
    BuildContext context,
    RentalVerification verification, {
    required String action,
  }) async {
    final step = await showRentalVerificationDialog(
      context,
      verification: verification,
      action: action,
    );
    if (!context.mounted) return;
    switch (step) {
      case RentalVerificationStep.idCard:
        await openIdentityAccount(context);
      case RentalVerificationStep.contactPhone:
        await openEditContact(context);
      case null:
        break;
    }
  }

  static Future<void> openIdentity(BuildContext context) =>
      openIdentityAccount(context);

  static Future<void> openPromptPayAccount(BuildContext context) {
    return context.push<void>(promptPayAccount);
  }

  static Future<void> openIdentityAccount(BuildContext context) async {
    if (!await AuthGuard.requireAuth(
          context,
          title: 'เข้าสู่ระบบเพื่อดูข้อมูลบัตรประชาชน',
          message: 'กรุณาเข้าสู่ระบบเพื่อจัดการข้อมูลส่วนตัวของคุณ',
        ) ||
        !context.mounted)
      return;
    return context.push<void>(identityAccount);
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

  static Future<void> openRentalStatus(
    BuildContext context, {
    bool isLender = false,
  }) {
    return context.push<void>(
      isLender ? '$rentalStatus?role=lender' : rentalStatus,
    );
  }

  static Future<void> openRentalHandover(
    BuildContext context, {
    BookingRequestData? bookingData,
    Map<String, dynamic>? trackingArgs,
    bool? isOwner,
    DateTime? startDate,
    bool pickupOnly = false,
  }) {
    final rawStartDate = trackingArgs?['startDate'];
    final parsedStartDate = rawStartDate is DateTime
        ? rawStartDate
        : DateTime.tryParse(rawStartDate?.toString() ?? '');

    final page = RentalHandoverPage(
      bookingData:
          bookingData ?? (trackingArgs?['bookingData'] as BookingRequestData?),
      itemTitle: trackingArgs?['itemTitle'] as String?,
      itemImageUrl: trackingArgs?['itemImageUrl'] as String?,
      pickupLocation: trackingArgs?['pickupLocation'] as String?,
      pickupAddress: trackingArgs?['pickupAddress'] as String?,
      pickupLatitude: (trackingArgs?['pickupLatitude'] as num?)?.toDouble(),
      pickupLongitude: (trackingArgs?['pickupLongitude'] as num?)?.toDouble(),
      ownerName: trackingArgs?['ownerName'] as String?,
      ownerPhone: trackingArgs?['ownerPhone'] as String?,
      periodText: trackingArgs?['periodText'] as String?,
      totalPrice: (trackingArgs?['totalPrice'] as num?)?.toDouble(),
      conversationId: trackingArgs?['conversationId'] as String?,
      statusCode: trackingArgs?['statusCode'] as String?,
      bookingId: (trackingArgs?['bookingId'] as num?)?.toInt(),
      startDate: startDate ?? parsedStartDate,
      isOwner: isOwner ?? (trackingArgs?['isOwner'] as bool?),
      requireBookingId: true,
      pickupOnly: pickupOnly,
      returnToPreviousChat: ModalRoute.of(context)?.settings.name == chatDetail,
    );

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: rentalHandover),
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

  static Future<void> openItemPreview(
    BuildContext context, {
    required ItemDetail item,
    required List<RentalItemPhoto> photos,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => ItemDetailBloc(
          initialItem: item,
          getItem: GetItemDetailUseCase(
            ItemDetailRepositoryImpl(ItemDetailRemoteDataSource()),
          ),
          updateItem: UpdateItemUseCase(
            ItemDetailRepositoryImpl(ItemDetailRemoteDataSource()),
          ),
        ),
        child: ItemDetailScreen(
          itemId: item.id,
          preview: true,
          previewItem: item,
          previewPhotos: photos,
        ),
      ),
    ),
  );

  static Future<void> openItemDetail(
    BuildContext context, {
    required int itemId,
    bool ownerLoadingLayout = false,
  }) {
    return context.push<void>(
      '/items/$itemId',
      extra: ItemDetailRouteArgs(ownerLoadingLayout: ownerLoadingLayout),
    );
  }

  static Future<void> openSearch(
    BuildContext context, {
    List<FeedItem>? curatedItems,
    String? initialQuery,
    String? initialCategoryId,
    int? minPrice,
    int? maxPrice,
    double? minRating,
    List<FeedCategory>? categories,
    ValueChanged<String>? onCategoryInterest,
  }) {
    try {
      return context.push<void>(
        search,
        extra: {
          'curatedItems': ?curatedItems,
          'query': ?initialQuery,
          'categoryId': ?initialCategoryId,
          'minPrice': ?minPrice,
          'maxPrice': ?maxPrice,
          'minRating': ?minRating,
          'categories': ?categories,
          'onCategoryInterest': ?onCategoryInterest,
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

  static Future<void> openItemAutoReply(
    BuildContext context, {
    required ItemDetail item,
  }) {
    return context.push<void>('/items/${item.id}/auto-reply', extra: item);
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
    final route = rentalId != null
        ? '/rental/return/$rentalId'
        : rentalReturnDemo;
    return context.push<void>(route, extra: isLender);
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
