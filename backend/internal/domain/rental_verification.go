package domain

type RentalVerification struct {
	IDCardApproved    bool `json:"id_card_approved"`
	ContactPhoneSaved bool `json:"contact_phone_saved"`
	IdentityPending   bool `json:"identity_pending"`
}

func (v RentalVerification) Complete() bool {
	return v.IDCardApproved && v.ContactPhoneSaved
}

type RentalVerificationRequired struct {
	Verification RentalVerification
}

func (*RentalVerificationRequired) Error() string { return "rental_verification_required" }
