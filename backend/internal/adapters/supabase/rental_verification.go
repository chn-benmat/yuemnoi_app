package supabase

import (
	"encoding/json"
	"errors"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

func mapRentalVerificationError(err error) error {
	var requestErr *postgrest.RequestError
	if errors.As(err, &requestErr) && requestErr.Message == "rental_verification_required" {
		var verification domain.RentalVerification
		if json.Unmarshal([]byte(requestErr.Details), &verification) == nil && !verification.Complete() {
			return &domain.RentalVerificationRequired{Verification: verification}
		}
	}
	return err
}
