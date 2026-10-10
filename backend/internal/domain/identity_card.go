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
	Blocks       []OCRBlock   `json:"blocks"`
	Alternatives [][]OCRBlock `json:"alternatives,omitempty"`
}

// IdentityCardFields ช่วยจัดรูปแบบข้อความที่อ่านได้ ผู้ใช้และเจ้าหน้าที่ต้องตรวจซ้ำเสมอ
// ค่าที่ขัดแย้ง อ่านไม่ชัด หรือไม่มีหัวข้อกำกับจะไม่ถูกเดาเติมลงแบบฟอร์ม
func IdentityCardFields(result *IdentityOCR, minimum float64) map[string]string {
	fields := map[string]string{}
	if result == nil {
		return fields
	}
	readings := append([][]OCRBlock{result.Blocks}, result.Alternatives...)
	candidates := map[string]map[string]bool{}
	for _, blocks := range readings {
		for field, values := range identityCardReading(blocks, minimum) {
			if candidates[field] == nil {
				candidates[field] = map[string]bool{}
			}
			for value := range values {
				candidates[field][value] = true
			}
		}
	}
	for field, values := range candidates {
		if len(values) == 1 {
			for value := range values {
				fields[field] = value
			}
		}
	}
	if fields["lifetime"] != "" && fields["expires_on"] != "" {
		delete(fields, "lifetime")
		delete(fields, "expires_on")
	}
	return fields
}

func identityCardReading(reading []OCRBlock, minimum float64) map[string]map[string]bool {
	blocks := make([]OCRBlock, 0, len(reading))
	for _, b := range reading {
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
	spatial := append([]OCRBlock(nil), blocks...)
	for _, l := range lines {
		sort.SliceStable(l.parts, func(i, j int) bool { return l.parts[i].X < l.parts[j].X })
		segment := l.parts[0]
		flush := func() {
			texts = append(texts, segment.Text)
			spatial = append(spatial, segment)
		}
		for _, p := range l.parts[1:] {
			// ช่องว่างระหว่างคอลัมน์ไม่ใช่ช่องว่างระหว่างคำ ห้ามรวมวันออกบัตรกับวันหมดอายุ
			if p.X-(segment.X+segment.Width) > 3*math.Max(segment.Height, p.Height) {
				flush()
				segment = p
				continue
			}
			bottom := math.Max(segment.Y+segment.Height, p.Y+p.Height)
			segment.Y = math.Min(segment.Y, p.Y)
			segment.Height = bottom - segment.Y
			segment.Width = math.Max(segment.X+segment.Width, p.X+p.Width) - segment.X
			segment.Text += " " + p.Text
		}
		flush()
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
	candidates := map[string]map[string]bool{}
	if len(ids) > 0 {
		candidates["citizen_id"] = ids
	}
	add := func(field, value string) {
		if value == "" {
			return
		}
		if candidates[field] == nil {
			candidates[field] = map[string]bool{}
		}
		candidates[field][value] = true
	}
	// ค้นวันที่จากกล่องใกล้หัวข้อในคอลัมน์เดียว รองรับวันที่ที่พิมพ์อยู่เหนือหัวข้อ
	dateLabels := []struct {
		field  string
		labels []string
	}{
		{"birth_date", []string{"วันเกิด", "เกิดวันที่", "date of birth"}},
		{"expires_on", []string{"วันบัตรหมดอายุ", "วันหมดอายุ", "date of expiry", "date of expiration"}},
	}
	for _, label := range spatial {
		for _, spec := range dateLabels {
			if value, ok := afterCardLabel(label.Text, spec.labels); ok {
				add(spec.field, cardDate(value))
				if cardDate(value) == "" {
					for _, nearby := range nearbyCardDates(label, spatial) {
						add(spec.field, nearby)
					}
				}
			}
		}
	}
	firsts, lasts := map[string]bool{}, map[string]bool{}
	surnameLabel := false
	for i, s := range texts {
		for _, spec := range dateLabels {
			if value, ok := afterCardLabel(s, spec.labels); ok {
				add(spec.field, cardDate(value))
			}
		}
		if value, ok := afterCardLabel(s, []string{"ชื่อตัวและชื่อสกุล", "ชื่อและนามสกุล", "ชื่อตัว", "ชื่อ"}); ok {
			if value == "" && i+1 < len(texts) {
				value = texts[i+1]
			}
			if validCardName(value) {
				firsts[value] = true
			}
		}
		if value, ok := afterCardLabel(s, []string{"นามสกุล"}); ok {
			surnameLabel = true
			if value == "" && i+1 < len(texts) {
				value = texts[i+1]
			}
			if validCardName(value) {
				lasts[value] = true
			}
		}
		if strings.Contains(s, "ตลอดชีพ") || strings.Contains(strings.ToLower(s), "lifetime") {
			add("lifetime", "true")
		}
	}
	for first := range firsts {
		if len(lasts) == 0 && !surnameLabel {
			add("legal_name", first)
		}
		for last := range lasts {
			name := first
			if !strings.HasSuffix(name, " "+last) {
				name += " " + last
			}
			add("legal_name", name)
		}
	}
	return candidates
}

func nearbyCardDates(label OCRBlock, blocks []OCRBlock) []string {
	values := map[string]bool{}
	for _, b := range blocks {
		value := cardDate(b.Text)
		if value == "" || label.Width <= 0 || b.Width <= 0 {
			continue
		}
		overlap := math.Min(label.X+label.Width, b.X+b.Width) - math.Max(label.X, b.X)
		distance := math.Abs((label.Y + label.Height/2) - (b.Y + b.Height/2))
		if overlap >= math.Min(label.Width, b.Width)/2 && distance <= 2.5*math.Max(label.Height, b.Height) {
			values[value] = true
		}
	}
	dates := make([]string, 0, len(values))
	for value := range values {
		dates = append(dates, value)
	}
	return dates
}

func afterCardLabel(s string, labels []string) (string, bool) {
	input := []rune(strings.TrimSpace(s))
	for _, label := range labels {
		index, matched := 0, true
		for _, expected := range label {
			if cardLabelSeparator(expected) {
				continue
			}
			for index < len(input) && cardLabelSeparator(input[index]) {
				index++
			}
			if index == len(input) || unicode.ToLower(input[index]) != expected {
				matched = false
				break
			}
			index++
		}
		if matched {
			for index < len(input) && cardLabelSeparator(input[index]) {
				index++
			}
			return strings.Join(strings.Fields(strings.Trim(string(input[index:]), " :：")), " "), true
		}
	}
	return "", false
}

// ผ่อนเฉพาะหัวข้อบนบัตรเมื่อ OCR ทำวรรณยุกต์หรือสระบนล่างหล่น ไม่แก้ชื่อหรือข้อมูลจริง
func cardLabelSeparator(r rune) bool {
	return unicode.IsSpace(r) || (r >= '\u0e00' && r <= '\u0e7f' && unicode.Is(unicode.Mn, r))
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
	if _, labelled := afterCardLabel(s, []string{"ชื่อ", "นามสกุล", "วันเกิด", "เกิดวันที่", "วันหมดอายุ", "วันบัตรหมดอายุ", "วันออกบัตร", "ที่อยู่", "สัญชาติ"}); labelled {
		return false
	}
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
	if len(parts) < 3 {
		return ""
	}
	// OCR อาจแยกจุดในชื่อเดือนเป็นคนละคำ เช่น ม. ค. ให้รวมเฉพาะส่วนชื่อเดือน
	parts = []string{parts[0], strings.Join(parts[1:len(parts)-1], ""), parts[len(parts)-1]}
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
