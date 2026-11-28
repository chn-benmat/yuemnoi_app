package geocoding

import (
	"regexp"
	"strings"
	"unicode"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

var housePrefix = regexp.MustCompile(`^([0-9]+(?:\s*[/-]\s*[0-9]+)*)(.*)$`)
var houseSeparator = regexp.MustCompile(`\s*([/-])\s*`)
var englishAddressWord = regexp.MustCompile(`(?i)\b(soi|road|rd|street|avenue|lane|alley|thanon|bangkok)\b`)

func normalizeThaiDigits(text string) string {
	return strings.Map(func(r rune) rune {
		if r >= '๐' && r <= '๙' {
			return '0' + r - '๐'
		}
		return r
	}, text)
}

func normalizePlaceQuery(query string) (normalized, number, area string) {
	query = normalizeThaiDigits(query)
	query = strings.NewReplacer("ถ.", "ถนน ", "ซ.", "ซอย ", "ต.", "ตำบล ", "อ.", "อำเภอ ", "จ.", "จังหวัด ", "กทม.", "กรุงเทพมหานคร", "กรุงเทพฯ", "กรุงเทพมหานคร").Replace(query)
	query = strings.TrimSpace(query)
	explicitHouse := false
	for _, prefix := range []string{"บ้านเลขที่", "เลขที่"} {
		if remaining, found := strings.CutPrefix(query, prefix); found {
			explicitHouse = true
			query = strings.TrimSpace(remaining)
			break
		}
	}
	query = strings.Join(strings.Fields(query), " ")
	query = strings.NewReplacer("ถนน ", "ถนน", "ซอย ", "ซอย").Replace(query)
	// เว้นวรรคระหว่างเลขบ้านกับชื่อถนนให้ผู้ให้บริการแยกคำได้
	number, area = splitHouseQuery(query, explicitHouse)
	if number != "" {
		query = strings.TrimSpace(number + " " + area)
	}
	return query, number, area
}

func splitHouseQuery(query string, explicitHouse bool) (number, area string) {
	match := housePrefix.FindStringSubmatch(query)
	if len(match) == 0 {
		return "", query
	}
	number = houseSeparator.ReplaceAllString(match[1], "$1")
	area = strings.TrimSpace(match[2])
	// ชื่อร้านที่ขึ้นต้นด้วยตัวเลข เช่น 7-Eleven หรือ 24 Fitness ยังเป็นคำค้นสถานที่
	if !explicitHouse && (strings.HasPrefix(area, "-") || (number == "7-11" && area == "") ||
		(area != "" && !hasThaiText(area) && !strings.Contains(number, "/") && !englishAddressWord.MatchString(area))) {
		return "", query
	}
	return number, area
}

func hasHouseNumber(value, number string) bool {
	return houseSeparator.ReplaceAllString(strings.TrimSpace(normalizeThaiDigits(value)), "$1") == number
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
