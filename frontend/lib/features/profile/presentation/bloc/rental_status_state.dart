import '../../domain/entities/rental_booking.dart';

// คำอธิบาย: State สำหรับจัดการสถานะการเช่าและปล่อยเช่า
abstract class RentalStatusState {
  const RentalStatusState();
}

class RentalStatusInitial extends RentalStatusState {
  const RentalStatusInitial();
}

class RentalStatusLoading extends RentalStatusState {
  const RentalStatusLoading({this.previous});

  final RentalStatusLoaded? previous;
}

class RentalStatusLoaded extends RentalStatusState {
  final List<RentalBooking> rentingList;
  final List<RentalBooking> lendingList;

  const RentalStatusLoaded({
    required this.rentingList,
    required this.lendingList,
  });
}

class RentalStatusActionInProgress extends RentalStatusState {
  const RentalStatusActionInProgress();
}

class RentalStatusActionSuccess extends RentalStatusState {
  final String message;
  const RentalStatusActionSuccess(this.message);
}

class RentalStatusError extends RentalStatusState {
  final String message;
  final RentalStatusLoaded? previous;

  const RentalStatusError(this.message, {this.previous});
}
