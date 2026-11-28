package domain

import "errors"

// RentalOccupiedError บอกเหตุผลที่ฐานข้อมูลปฏิเสธคำขอเช่าเพราะอุปกรณ์ไม่ว่าง
// errors.Is(err, ErrItemRentalOccupied) ยังเป็นจริง เพื่อให้ผู้เรียกเดิมทำงานต่อได้
type RentalOccupiedError struct {
	Reason string
}

func (e *RentalOccupiedError) Error() string {
	if e.Reason == "" {
		return ErrItemRentalOccupied.Error()
	}
	return ErrItemRentalOccupied.Error() + ": " + e.Reason
}

func (*RentalOccupiedError) Is(target error) bool { return target == ErrItemRentalOccupied }

// rentalOccupiedMessages รับเฉพาะเหตุผลที่ฐานข้อมูลส่งมา เหตุผลอื่นใช้ข้อความรวมเดิม
var rentalOccupiedMessages = map[string]string{
	"item_unavailable":       "ประกาศนี้ปิดให้เช่าชั่วคราวหรือกำลังรอตรวจสอบ",
	"item_rented":            "อุปกรณ์นี้กำลังถูกเช่าอยู่ กรุณาต่อคิวเพื่อเช่าต่อ",
	"queue_held":             "มีผู้ได้คิวเช่าต่อก่อนคุณ กรุณารอคิวถัดไป",
	"queue_turn_unconfirmed": "ถึงคิวของคุณแล้ว กรุณากดยืนยันสิทธิ์ในการ์ดคิวก่อนส่งคำขอเช่า",
	"queue_turn_use_card":    "คุณได้สิทธิ์คิวแล้ว กรุณาส่งคำขอเช่าจากการ์ดคิวในแชต",
	"queue_turn_expired":     "สิทธิ์คิวของคุณหมดเวลาแล้ว กรุณาต่อคิวใหม่",
	"pickup_time_passed":     "เวลานัดรับต้องอยู่ภายในเวลาที่ระบบกำหนด กรุณาเลือกวันและเวลาใหม่",
}

const rentalOccupiedFallbackMessage = "อุปกรณ์นี้อยู่ระหว่างเช่าหรือมีคิวเช่าต่อ กรุณาตรวจสอบสิทธิ์อีกครั้ง"

// RentalOccupiedReason คืนเหตุผลที่รู้จักและข้อความสำหรับผู้ใช้ เหตุผลที่ไม่รู้จักคืนค่าว่าง
func RentalOccupiedReason(err error) (reason, message string) {
	var occupied *RentalOccupiedError
	if errors.As(err, &occupied) {
		if text, known := rentalOccupiedMessages[occupied.Reason]; known {
			return occupied.Reason, text
		}
	}
	return "", rentalOccupiedFallbackMessage
}
