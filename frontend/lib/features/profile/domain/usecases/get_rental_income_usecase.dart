import '../entities/rental_income.dart';
import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงข้อมูลสรุปรายได้และประวัติรายรับจากการปล่อยเช่า
class GetRentalIncomeUseCase {
  final RentalManagementRepository repository;

  const GetRentalIncomeUseCase(this.repository);

  Future<RentalIncomeSummary> execute() {
    return repository.getRentalIncome();
  }
}
