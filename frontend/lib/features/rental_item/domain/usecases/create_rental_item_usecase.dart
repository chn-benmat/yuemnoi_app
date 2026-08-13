import '../entities/rental_item.dart';
import '../repositories/rental_item_repository.dart';

class CreateRentalItemUseCase {
  const CreateRentalItemUseCase(this.repository);

  final RentalItemRepository repository;

  Future<RentalItem> execute(RentalItemDraft draft) => repository.create(draft);

  void close() => repository.close();
}
