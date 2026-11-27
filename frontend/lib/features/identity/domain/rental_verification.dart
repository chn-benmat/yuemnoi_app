import 'package:equatable/equatable.dart';

class RentalVerification extends Equatable {
  const RentalVerification({
    required this.idCardApproved,
    required this.contactPhoneSaved,
    required this.identityPending,
  });

  final bool idCardApproved;
  final bool contactPhoneSaved;
  final bool identityPending;

  bool get isComplete => idCardApproved && contactPhoneSaved;

  static RentalVerification? fromJson(Object? value) {
    if (value case {
      'id_card_approved': final bool card,
      'contact_phone_saved': final bool phone,
      'identity_pending': final bool pending,
    }) {
      return RentalVerification(
        idCardApproved: card,
        contactPhoneSaved: phone,
        identityPending: pending,
      );
    }
    return null;
  }

  @override
  List<Object?> get props => [
    idCardApproved,
    contactPhoneSaved,
    identityPending,
  ];
}

class RentalVerificationRequired implements Exception {
  const RentalVerificationRequired(this.verification);

  final RentalVerification verification;

  static RentalVerificationRequired? fromJson(Object? value) {
    if (value case {
      'code': 'rental_verification_required',
      'rental_verification': final Object? data,
    }) {
      final verification = RentalVerification.fromJson(data);
      if (verification != null && !verification.isComplete) {
        return RentalVerificationRequired(verification);
      }
    }
    return null;
  }
}
