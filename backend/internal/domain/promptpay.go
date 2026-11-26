package domain

import (
	"context"
	"fmt"
	"regexp"
)

type PromptPayAccount struct {
	IDType             string `json:"promptpay_id_type,omitempty"`
	Phone              string `json:"promptpay_phone,omitempty"`
	NationalIDLastFour string `json:"national_id_last_four,omitempty"`
}

type PromptPayAccountRepository interface {
	GetPromptPayAccount(ctx context.Context, userID string) (PromptPayAccount, error)
	UpdatePromptPayAccount(ctx context.Context, userID, phone, nationalID string) (PromptPayAccount, error)
}

var promptPayMobilePattern = regexp.MustCompile(`^0[689][0-9]{8}$`)

func IsPromptPayMobile(phone string) bool {
	return promptPayMobilePattern.MatchString(phone)
}

func IsPromptPayNationalID(id string) bool {
	if !ValidThaiCitizenID(id) {
		return false
	}
	// หลักสุดท้ายใช้ตรวจความถูกต้องของ 12 หลักแรก
	sum := 0
	for i := 0; i < 12; i++ {
		sum += int(id[i]-'0') * (13 - i)
	}
	return (11-sum%11)%10 == int(id[12]-'0')
}

func PromptPayQR(phone, nationalID string, satang int64) string {
	if satang < 1 || satang > 999999999999 {
		return ""
	}
	field := func(tag, value string) string {
		return fmt.Sprintf("%s%02d%s", tag, len(value), value)
	}
	// Tag 29 ใช้ 01 สำหรับเบอร์รูปแบบ 0066 และ 02 สำหรับเลขบัตรประชาชน
	var identifier string
	switch {
	case nationalID == "" && IsPromptPayMobile(phone):
		identifier = field("01", "0066"+phone[1:])
	case phone == "" && IsPromptPayNationalID(nationalID):
		identifier = field("02", nationalID)
	default:
		return ""
	}
	account := field("00", "A000000677010111") + identifier
	amount := fmt.Sprintf("%d.%02d", satang/100, satang%100)
	payload := "000201010212" + field("29", account) + "5303764" + field("54", amount) + "5802TH6304"
	// EMV ใช้ CRC-16/CCITT-FALSE และรวม Tag กับความยาวของ CRC ในข้อมูลที่คำนวณ
	crc := uint16(0xffff)
	for i := 0; i < len(payload); i++ {
		crc ^= uint16(payload[i]) << 8
		for bit := 0; bit < 8; bit++ {
			if crc&0x8000 != 0 {
				crc = (crc << 1) ^ 0x1021
			} else {
				crc <<= 1
			}
		}
	}
	return fmt.Sprintf("%s%04X", payload, crc)
}
