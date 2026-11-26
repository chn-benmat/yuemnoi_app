// คำอธิบาย: Entity สำหรับข้อมูลสรุปรายได้และประวัติรายรับจากการปล่อยเช่า
class RentalIncomeSummary {
  final int totalSatang;
  final List<RentalIncomeEntry> transactions;

  const RentalIncomeSummary({
    required this.totalSatang,
    required this.transactions,
  });
}

class RentalIncomeEntry {
  final String itemName;
  final DateTime confirmedAt;
  final String paymentMethod;
  final int amountSatang;

  const RentalIncomeEntry({
    required this.itemName,
    required this.confirmedAt,
    required this.paymentMethod,
    required this.amountSatang,
  });
}
