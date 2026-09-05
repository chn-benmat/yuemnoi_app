import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/wallet/presentation/bloc/wallet_cubit.dart';
import 'package:frontend/features/wallet/presentation/bloc/wallet_state.dart';

void main() {
  test('wallet top up stays local and updates mock balance', () async {
    final cubit = WalletCubit();
    addTearDown(cubit.close);

    await cubit.topUp(amount: 300);

    expect(cubit.state.status, WalletStatus.success);
    expect(cubit.state.balance, 1500);
    expect(cubit.state.transactions.first.title, 'เติมเงินจำลอง');
    expect(cubit.state.transactions.first.amount, 300);
  });
}
