package domain

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"
)

// เลขที่ผ่าน checksum ยังไม่ได้ยืนยันว่าบัตรออกโดยหน่วยงานรัฐ
func ValidThaiCitizenID(id string) bool {
	if len(id) != 13 {
		return false
	}
	sum := 0
	for i := 0; i < 13; i++ {
		if id[i] < '0' || id[i] > '9' {
			return false
		}
		if i < 12 {
			sum += int(id[i]-'0') * (13 - i)
		}
	}
	return (11-sum%11)%10 == int(id[12]-'0')
}
func CitizenHMAC(id string, key []byte) string {
	m := hmac.New(sha256.New, key)
	m.Write([]byte(id))
	return hex.EncodeToString(m.Sum(nil))
}
func EncryptIdentity(data, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	g, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, g.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(g.Seal(nonce, nonce, data, []byte("identity-v1"))), nil
}
func IdentityAge(birth string, now time.Time) (bool, error) {
	dob, err := time.Parse("2006-01-02", birth)
	if err != nil || dob.Year() < 1 || dob.After(now) {
		return false, errors.New("invalid_birth_date")
	}
	return dob.AddDate(20, 0, 0).After(now), nil
}

func DecryptIdentity(encoded string, key []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	g, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) < g.NonceSize() {
		return nil, errors.New("invalid_ciphertext")
	}
	return g.Open(nil, data[:g.NonceSize()], data[g.NonceSize():], []byte("identity-v1"))
}
