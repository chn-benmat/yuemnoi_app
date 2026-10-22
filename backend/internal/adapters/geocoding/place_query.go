package geocoding

import (
	"regexp"
	"strings"
	"unicode"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

var housePrefix = regexp.MustCompile(`^([0-9]+(?:[/-][0-9]+)*)(.*)$`)

func normalizePlaceQuery(query string) string {
	query = strings.Map(func(r rune) rune {
		if r >= '๐' && r <= '๙' {
			return '0' + r - '๐'
		}
		return r
	}, query)
	query = strings.NewReplacer("ถ.", "ถนน ", "ซ.", "ซอย ", "ต.", "ตำบล ", "อ.", "อำเภอ ", "จ.", "จังหวัด ", "กทม.", "กรุงเทพมหานคร", "กรุงเทพฯ", "กรุงเทพมหานคร").Replace(query)
	query = strings.TrimSpace(query)
	for _, prefix := range []string{"บ้านเลขที่", "เลขที่"} {
		query = strings.TrimSpace(strings.TrimPrefix(query, prefix))
	}
	query = strings.Join(strings.Fields(query), " ")
	return strings.NewReplacer("ถนน ", "ถนน", "ซอย ", "ซอย").Replace(query)
}

func splitHouseQuery(query string) (number, area string) {
	match := housePrefix.FindStringSubmatch(query)
	if len(match) == 0 {
		return "", query
	}
	// ชื่อร้านที่ขึ้นต้นด้วยตัวเลข เช่น 7-Eleven ไม่ใช่เลขที่บ้าน
	if strings.HasPrefix(match[2], "-") {
		return "", query
	}
	return match[1], strings.TrimSpace(match[2])
}

func matchesPlaceArea(place domain.Place, query string) bool {
	normalize := func(text string) string {
		return strings.Map(func(r rune) rune {
			if unicode.IsSpace(r) || strings.ContainsRune(",.-", r) {
				return -1
			}
			return unicode.ToLower(r)
		}, text)
	}
	address := normalize(place.Name + " " + place.DisplayName + " " + place.OriginalName)
	for _, word := range strings.Fields(query) {
		for _, prefix := range []string{"ถนน", "ซอย", "ตำบล", "อำเภอ", "จังหวัด", "แขวง", "เขต"} {
			word = strings.TrimPrefix(word, prefix)
		}
		// Photon จับคู่คำอังกฤษกับชื่อไทยได้ แม้ข้อความที่คืนมาไม่มีตัวสะกดอังกฤษ
		if !hasThaiText(word) && strings.IndexFunc(word, func(r rune) bool { return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') }) >= 0 {
			continue
		}
		if word != "" && !strings.Contains(address, normalize(word)) {
			return false
		}
	}
	return true
}
