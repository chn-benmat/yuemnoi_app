import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/rental_booking.dart';
import 'package:frontend/features/profile/domain/entities/rental_income.dart';
import 'package:frontend/features/profile/domain/repositories/rental_management_repository.dart';
import 'package:frontend/features/profile/domain/usecases/get_rental_bookings_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/get_rental_history_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/get_rental_income_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_booking_status_usecase.dart';

class FakeRentalManagementRepository implements RentalManagementRepository {
  final List<RentalBooking> rentingList = [
    const RentalBooking(
      bookingId: 1,
      title: 'Sony A7 IV',
      partnerName: 'Owner 1',
      partnerRole: 'เจ้าของอุปกรณ์',
      status: 'ยืนยันแล้ว / นัดรับของ',
      statusCode: 'confirmed',
    ),
  ];

  final List<RentalBooking> lendingList = [
    const RentalBooking(
      bookingId: 2,
      title: 'MacBook Pro',
      partnerName: 'Renter 1',
      partnerRole: 'ผู้เช่า',
      status: 'ยืนยันแล้ว / นัดรับของ',
      statusCode: 'confirmed',
      isOwner: true,
    ),
  ];

  int? lastUpdatedBookingId;
  String? lastUpdatedStatus;

  @override
  Future<List<RentalBooking>> getRentingBookings(String userId) async {
    return rentingList;
  }

  @override
  Future<List<RentalBooking>> getLendingBookings(String userId) async {
    return lendingList;
  }

  @override
  Future<List<RentalBooking>> getRentalHistory(String userId) async {
    return rentingList;
  }

  @override
  Future<void> updateBookingStatus({
    required int bookingId,
    required String status,
  }) async {
    lastUpdatedBookingId = bookingId;
    lastUpdatedStatus = status;
  }

  @override
  Future<RentalIncomeSummary> getRentalIncome() async {
    return RentalIncomeSummary(
      totalSatang: 240000,
      transactions: [
        RentalIncomeEntry(
          itemName: 'Sony A7 IV',
          confirmedAt: DateTime.utc(2026, 8, 12),
          amountSatang: 240000,
          paymentMethod: 'cash',
        ),
      ],
    );
  }
}

void main() {
  late FakeRentalManagementRepository repository;

  setUp(() {
    repository = FakeRentalManagementRepository();
  });

  group('Rental Management UseCases', () {
    test(
      'GetRentalBookingsUseCase returns renting and lending bookings',
      () async {
        final useCase = GetRentalBookingsUseCase(repository);

        final renting = await useCase.executeRenting('user1');
        final lending = await useCase.executeLending('user1');

        expect(renting.length, 1);
        expect(renting.first.title, 'Sony A7 IV');
        expect(lending.length, 1);
        expect(lending.first.title, 'MacBook Pro');
      },
    );

    test('UpdateBookingStatusUseCase delegates update to repository', () async {
      final useCase = UpdateBookingStatusUseCase(repository);

      await useCase.execute(bookingId: 42, status: 'active');

      expect(repository.lastUpdatedBookingId, 42);
      expect(repository.lastUpdatedStatus, 'active');
    });

    test('GetRentalHistoryUseCase returns booking history list', () async {
      final useCase = GetRentalHistoryUseCase(repository);

      final history = await useCase.execute('user1');

      expect(history.length, 1);
      expect(history.first.bookingId, 1);
    });

    test(
      'GetRentalIncomeUseCase returns income summary and transactions',
      () async {
        final useCase = GetRentalIncomeUseCase(repository);

        final income = await useCase.execute();

        expect(income.totalSatang, 240000);
        expect(income.transactions.length, 1);
        expect(income.transactions.first.itemName, 'Sony A7 IV');
      },
    );
  });
}
