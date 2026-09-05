// คำอธิบาย: Entity สำหรับข้อมูลสรุปรายได้และประวัติรายรับจากการปล่อยเช่า
class RentalIncomeSummary {
  final double totalIncome;
  final double pendingIncome;
  final List<RentalIncomeEntry> transactions;

  const RentalIncomeSummary({
    required this.totalIncome,
    required this.pendingIncome,
    required this.transactions,
  });
}

class RentalIncomeEntry {
  final String itemName;
  final String date;
  final String duration;
  final double amount;
  final String status;

  const RentalIncomeEntry({
    required this.itemName,
    required this.date,
    required this.duration,
    required this.amount,
    required this.status,
  });
}
