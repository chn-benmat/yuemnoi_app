package geocoding

import (
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"strings"
)

func hasThaiText(text string) bool {
	for _, r := range text {
		if r >= 'ก' && r <= '๛' {
			return true
		}
	}
	return false
}

func preferThaiPlace(place domain.Place, candidates ...string) domain.Place {
	if hasThaiText(place.Name) {
		return place
	}
	original := place.Name
	place.OriginalName = original
	place.Name = "จุดนัดรับที่เลือก"
	for _, candidate := range candidates {
		if hasThaiText(candidate) {
			place.Name = "จุดนัดรับบริเวณ" + candidate
			break
		}
	}
	// ไม่แปลชื่อเฉพาะที่ต้นทางไม่มีชื่อไทย ใช้ชื่อจุดนัดรับตามที่อยู่และเก็บชื่อเดิม
	if strings.HasPrefix(place.DisplayName, original) {
		place.DisplayName = place.Name + strings.TrimPrefix(place.DisplayName, original)
	}
	return place
}
