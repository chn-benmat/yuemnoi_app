import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/usecases/get_my_items_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/my_items_cubit.dart';
import 'package:frontend/features/profile/presentation/bloc/my_items_state.dart';

import '../../domain/usecases/user_items_usecases_test.dart';

void main() {
  group('MyItemsCubit', () {
    test('initial state is MyItemsInitial', () {
      final cubit = MyItemsCubit(
        getMyItems: GetMyItemsUseCase(FakeUserItemsRepository()),
      );
      expect(cubit.state, isA<MyItemsInitial>());
      cubit.close();
    });

    blocTest<MyItemsCubit, MyItemsState>(
      'loadMyItems emits [MyItemsLoading, MyItemsLoaded]',
      build: () => MyItemsCubit(
        getMyItems: GetMyItemsUseCase(FakeUserItemsRepository()),
      ),
      act: (cubit) => cubit.loadMyItems('u1'),
      expect: () => [
        isA<MyItemsLoading>(),
        isA<MyItemsLoaded>().having((s) => s.items.length, 'items.length', 1),
      ],
    );
  });
}
