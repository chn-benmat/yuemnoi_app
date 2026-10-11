package ports

import (
	"errors"
	"strings"

	"github.com/go-playground/validator/v10"
)

type identityDetailsRequest struct {
	NamePrefix    string `json:"name_prefix" validate:"required,oneof=นาย นางสาว นาง"`
	FirstName     string `json:"first_name" validate:"required,max=150"`
	LastName      string `json:"last_name" validate:"required,max=150"`
	AddressDetail string `json:"address_detail" validate:"required,max=500"`
	PostalCode    string `json:"postal_code" validate:"required,len=5,numeric"`
	Province      string `json:"province" validate:"required,max=100"`
	District      string `json:"district" validate:"required,max=100"`
	Subdistrict   string `json:"subdistrict" validate:"required,max=100"`
}

var identityDetailsValidator = validator.New()

func parseIdentityDetails(values map[string][]string) (*identityDetailsRequest, error) {
	details := &identityDetailsRequest{}
	fields := map[string]*string{
		"name_prefix": &details.NamePrefix, "first_name": &details.FirstName, "last_name": &details.LastName,
		"address_detail": &details.AddressDetail, "postal_code": &details.PostalCode,
		"province": &details.Province, "district": &details.District, "subdistrict": &details.Subdistrict,
	}
	present := false
	for key, target := range fields {
		if value, exists := values[key]; exists {
			present = true
			if len(value) > 0 {
				*target = strings.TrimSpace(value[0])
			}
		}
	}
	// แอปรุ่นเดิมยังส่งชื่อรวมได้ แต่แบบฟอร์มใหม่ต้องส่งข้อมูลครบทุกช่อง
	if !present {
		return nil, nil
	}
	if err := identityDetailsValidator.Struct(details); err != nil {
		return nil, err
	}
	if strings.HasPrefix(details.PostalCode, "0") {
		return nil, errors.New("invalid_postal_code")
	}
	return details, nil
}
