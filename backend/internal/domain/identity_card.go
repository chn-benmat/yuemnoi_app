package domain

import (
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// OCRBlock เก็บตัวอักษรและตำแหน่งสัมพัทธ์จากโมเดล ไม่มีการเก็บภาพถาวร
type OCRBlock struct {
	Text       string  `json:"text"`
	Confidence float64 `json:"confidence"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	Width      float64 `json:"width"`
	Height     float64 `json:"height"`
}
type IdentityOCR struct {
	Blocks []OCRBlock `json:"blocks"`
}

// IdentityCardFields ช่วยจัดรูปแบบข้อความที่อ่านได้ ผู้ใช้และเจ้าหน้าที่ต้องตรวจซ้ำเสมอ
// ค่าที่ขัดแย้ง อ่านไม่ชัด หรือไม่มีหัวข้อกำกับจะไม่ถูกเดาเติมลงแบบฟอร์ม
func IdentityCardFields(result *IdentityOCR, minimum float64) map[string]string {
	fields := map[string]string{}
	if result == nil {
		return fields
	}
	blocks := make([]OCRBlock, 0, len(result.Blocks))
	for _, b := range result.Blocks {
		if b.Confidence < minimum || math.IsNaN(b.Confidence) || b.Height <= 0 || len(b.Text) > 1000 {
			continue
		}
		b.Text = strings.TrimSpace(b.Text)
		if b.Text != "" {
			blocks = append(blocks, b)
		}
	}
	sort.SliceStable(blocks, func(i, j int) bool { return blocks[i].Y < blocks[j].Y })
	type line struct {
		y, height float64
		parts     []OCRBlock
	}
	lines := []line{}
	for _, b := range blocks {
		center := b.Y + b.Height/2
		if len(lines) > 0 && math.Abs(lines[len(lines)-1].y-center) < math.Min(lines[len(lines)-1].height, b.Height)/2 {
			lines[len(lines)-1].parts = append(lines[len(lines)-1].parts, b)
		} else {
			lines = append(lines, line{center, b.Height, []OCRBlock{b}})
		}
	}
	texts := []string{}
	for _, l := range lines {
		sort.SliceStable(l.parts, func(i, j int) bool { return l.parts[i].X < l.parts[j].X })
		parts := []string{}
		for _, p := range l.parts {
			parts = append(parts, p.Text)
		}
		texts = append(texts, strings.Join(parts, " "))
	}
	ids := map[string]bool{}
	for _, b := range blocks {
		if id := cardDigits(b.Text); ValidThaiCitizenID(id) {
			ids[id] = true
		}
	}
	for _, s := range texts {
		if id := cardDigits(s); ValidThaiCitizenID(id) {
			ids[id] = true
		}
		if value, ok := afterCardLabel(s, []string{"เลขประจำตัวประชาชน", "เลขประจำตัว", "identification number", "id number"}); ok {
			if id := cardDigits(value); ValidThaiCitizenID(id) {
				ids[id] = true
			}
		}
	}
	if len(ids) == 1 {
		for id := range ids {
			fields["citizen_id"] = id
		}
	}
	candidates := map[string]map[string]bool{}
	add := func(field, value string) {
		if value == "" {
			return
		}
		if candidates[field] == nil {
			candidates[field] = map[string]bool{}
		}
		candidates[field][value] = true
	}
	var first, last string
	for i, s := range texts {
		for _, spec := range []struct {
			field  string
			labels []string
		}{
			{"birth_date", []string{"วันเกิด", "เกิดวันที่", "date of birth"}},
			{"expires_on", []string{"วันหมดอายุ", "date of expiry", "date of expiration"}},
		} {
			if value, ok := afterCardLabel(s, spec.labels); ok {
				if value == "" && i+1 < len(texts) {
					value = texts[i+1]
				}
				add(spec.field, cardDate(value))
			}
		}
		if value, ok := afterCardLabel(s, []string{"ชื่อตัวและชื่อสกุล", "ชื่อและนามสกุล", "ชื่อตัว", "ชื่อ"}); ok {
			if value == "" && i+1 < len(texts) {
				value = texts[i+1]
			}
			if validCardName(value) {
				first = value
			}
		}
		if value, ok := afterCardLabel(s, []string{"นามสกุล"}); ok && validCardName(value) {
			last = value
		}
		if strings.Contains(s, "ตลอดชีพ") || strings.Contains(strings.ToLower(s), "lifetime") {
			fields["lifetime"] = "true"
		}
	}
	if first != "" {
		if last != "" {
			first += " " + last
		}
		fields["legal_name"] = first
	}
	for field, values := range candidates {
		if len(values) == 1 {
			for value := range values {
				fields[field] = value
			}
		}
	}
	if fields["lifetime"] == "true" {
		delete(fields, "expires_on")
	}
	return fields
}

func afterCardLabel(s string, labels []string) (string, bool) {
	lower := strings.ToLower(strings.TrimSpace(s))
	for _, label := range labels {
		if strings.HasPrefix(lower, label) {
			return strings.Trim(strings.TrimSpace(s[len(label):]), ":："), true
		}
	}
	return "", false
}
func cardDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '๐' && r <= '๙' {
			r = '0' + r - '๐'
		}
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		} else if r != '-' && !unicode.IsSpace(r) {
			return ""
		}
	}
	return b.String()
}
func validCardName(s string) bool {
	thai := false
	for _, r := range s {
		if unicode.IsDigit(r) {
			return false
		}
		if r >= 'ก' && r <= '๙' {
			thai = true
		}
	}
	return thai && len([]rune(s)) >= 3 && len([]rune(s)) <= 150
}
func cardDate(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	for _, r := range s {
		if r >= '๐' && r <= '๙' {
			s = strings.ReplaceAll(s, string(r), string('0'+r-'๐'))
		}
	}
	s = strings.NewReplacer(".", "", "/", " ", "-", " ").Replace(s)
	var separated strings.Builder
	var previous rune
	for _, r := range s {
		if previous != 0 && !unicode.IsSpace(previous) && !unicode.IsSpace(r) && unicode.IsDigit(previous) != unicode.IsDigit(r) {
			separated.WriteByte(' ')
		}
		separated.WriteRune(r)
		previous = r
	}
	parts := strings.Fields(separated.String())
	if len(parts) != 3 {
		return ""
	}
	day, _ := strconv.Atoi(parts[0])
	year, _ := strconv.Atoi(parts[2])
	month, _ := strconv.Atoi(parts[1])
	if len(parts[0]) == 4 {
		year, _ = strconv.Atoi(parts[0])
		day, _ = strconv.Atoi(parts[2])
	}
	months := [][]string{
		{"มค", "มกราคม", "jan", "january"}, {"กพ", "กุมภาพันธ์", "feb", "february"},
		{"มีค", "มีนาคม", "mar", "march"}, {"เมย", "เมษายน", "apr", "april"},
		{"พค", "พฤษภาคม", "may"}, {"มิย", "มิถุนายน", "jun", "june"},
		{"กค", "กรกฎาคม", "jul", "july"}, {"สค", "สิงหาคม", "aug", "august"},
		{"กย", "กันยายน", "sep", "sept", "september"}, {"ตค", "ตุลาคม", "oct", "october"},
		{"พย", "พฤศจิกายน", "nov", "november"}, {"ธค", "ธันวาคม", "dec", "december"},
	}
	if month == 0 {
		for i, names := range months {
			for _, name := range names {
				if parts[1] == name {
					month = i + 1
				}
			}
		}
	}
	if year > 2400 {
		year -= 543
	}
	if year < 1900 || year > 2200 || month < 1 || month > 12 || day < 1 || day > 31 {
		return ""
	}
	d := time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC)
	if d.Day() != day || int(d.Month()) != month {
		return ""
	}
	return d.Format("2006-01-02")
}
