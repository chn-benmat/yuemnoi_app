package domain_test

import (
	domain "github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"testing"
)

func TestValidThaiCitizenID(t *testing.T) {
	for _, tc := range []struct {
		name string
		id   string
		want bool
	}{
		{name: "accepts number without matching checksum for staff review", id: "1234567890000", want: true},
		{name: "preserves leading zeros", id: "0000000000000", want: true},
		{name: "rejects empty number", id: "", want: false},
		{name: "rejects fewer than 13 digits", id: "123456789000", want: false},
		{name: "rejects more than 13 digits", id: "12345678900000", want: false},
		{name: "rejects non-digit characters", id: "123456789000a", want: false},
		{name: "rejects signed number", id: "+123456789000", want: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := domain.ValidThaiCitizenID(tc.id); got != tc.want {
				t.Errorf("ValidThaiCitizenID(%q) = %v, want %v", tc.id, got, tc.want)
			}
		})
	}
}
