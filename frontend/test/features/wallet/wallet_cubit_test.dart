import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/wallet/presentation/bloc/wallet_cubit.dart';
import 'package:frontend/features/wallet/presentation/bloc/wallet_state.dart';

void main() {
  group('WalletCubit', () {
    late WalletCubit walletCubit;

    setUp(() {
      walletCubit = WalletCubit();
    });

    tearDown(() {
      walletCubit.close();
    });

    test('initial state has default balance of 1200.0 and one transaction', () {
      expect(walletCubit.state.balance, 1200.0);
      expect(walletCubit.state.transactions.length, 1);
      expect(walletCubit.state.transactions.first.title, 'โอนเข้าบัญชี');
      expect(walletCubit.state.transactions.first.amount, 1200.0);
    });

    test('topUp increases balance and prepends new transaction', () async {
      await walletCubit.topUp(amount: 500.0, paymentMethod: 'PromptPay');

      expect(walletCubit.state.balance, 1700.0);
      expect(walletCubit.state.transactions.length, 2);
      expect(walletCubit.state.transactions.first.amount, 500.0);
      expect(walletCubit.state.status, WalletStatus.success);
    });
  });
}
