package ports

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// PushHandler จัดการการส่ง Push Notification ผ่าน FCM HTTP v1
type PushHandler struct{}

// NewPushHandler สร้าง PushHandler ใหม่
func NewPushHandler() *PushHandler {
	return &PushHandler{}
}

// SendChatPushRequest เป็น request body สำหรับส่ง push notification ของข้อความแชท

type SendChatPushRequest struct {
	ReceiverID     string `json:"receiver_id" binding:"required"`
	ConversationID string `json:"conversation_id" binding:"required"`
	MessageID      string `json:"message_id"`
	SenderName     string `json:"sender_name"`
	SenderAvatar   string `json:"sender_avatar"`
	Message        string `json:"message"`
}



// ServiceAccountKey โครงสร้างไฟล์ Service Account JSON ของ Firebase / Google Cloud
type ServiceAccountKey struct {
	Type                    string `json:"type"`
	ProjectID               string `json:"project_id"`
	PrivateKeyID            string `json:"private_key_id"`
	PrivateKey              string `json:"private_key"`
	ClientEmail             string `json:"client_email"`
	ClientID                string `json:"client_id"`
	AuthURI                 string `json:"auth_uri"`
	TokenURI                string `json:"token_uri"`
	AuthProviderX509CertURL string `json:"auth_provider_x509_cert_url"`
	ClientX509CertURL       string `json:"client_x509_cert_url"`
}

var (
	tokenMu        sync.Mutex
	cachedToken    string
	tokenExpiry    time.Time
	cachedSA       *ServiceAccountKey
	saLoaded       bool
	fcmTokenCache  sync.Map
	pushHttpClient = &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 20,
			IdleConnTimeout:     90 * time.Second,
		},
	}
)

type fcmCachedToken struct {
	token     string
	expiresAt time.Time
}

// loadServiceAccount โหลด Service Account จากไฟล์หรือ Environment
func loadServiceAccount() (*ServiceAccountKey, error) {
	if saLoaded && cachedSA != nil {
		return cachedSA, nil
	}

	// 1. ตรวจสอบจาก Environment Variable (Path หรือ JSON ตรงๆ)
	saPath := os.Getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
	saJSON := os.Getenv("FIREBASE_SERVICE_ACCOUNT_KEY")

	var data []byte
	var err error

	if saJSON != "" {
		data = []byte(saJSON)
	} else if saPath != "" {
		data, err = os.ReadFile(saPath)
		if err != nil {
			// ลองหา fallback path อื่นๆ
			for _, candidate := range []string{saPath, "service-account.json", "backend/service-account.json", "../service-account.json"} {
				if d, e := os.ReadFile(candidate); e == nil {
					data = d
					break
				}
			}
			if len(data) == 0 {
				return nil, fmt.Errorf("ไม่สามารถอ่านไฟล์ FIREBASE_SERVICE_ACCOUNT_PATH: %w", err)
			}
		}
	} else {
		// 2. Auto-discovery: หาไฟล์ JSON ที่อยู่ในโฟลเดอร์ต่างๆ
		candidates := []string{"service-account.json", "backend/service-account.json", "../service-account.json"}
		files, _ := filepath.Glob("*.json")
		candidates = append(candidates, files...)

		for _, f := range candidates {
			d, err := os.ReadFile(f)
			if err == nil && strings.Contains(string(d), "private_key") && strings.Contains(string(d), "client_email") {
				data = d
				log.Printf("พบ Firebase Service Account อัตโนมัติ: %s", f)
				break
			}
		}
	}

	if len(data) == 0 {
		return nil, fmt.Errorf("ไม่พบ Firebase Service Account กรุณาวางไฟล์ service-account.json ใน backend หรือตั้งค่า FIREBASE_SERVICE_ACCOUNT_PATH")
	}

	var sa ServiceAccountKey
	if err := json.Unmarshal(data, &sa); err != nil {
		return nil, fmt.Errorf("รูปแบบ Service Account JSON ไม่ถูกต้อง: %w", err)
	}

	cachedSA = &sa
	saLoaded = true
	return cachedSA, nil
}

// getGoogleOAuth2Token สร้าง OAuth2 Bearer Token จาก Service Account สำหรับเรียก FCM v1 API
func getGoogleOAuth2Token() (string, string, error) {
	tokenMu.Lock()
	defer tokenMu.Unlock()

	sa, err := loadServiceAccount()
	if err != nil {
		return "", "", err
	}

	if cachedToken != "" && time.Now().Before(tokenExpiry) {
		return cachedToken, sa.ProjectID, nil
	}

	// Parse Private Key
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return "", "", fmt.Errorf("ไม่สามารถถอดรหัส private_key ใน service account ได้")
	}

	parsedKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", "", fmt.Errorf("ParsePKCS8PrivateKey error: %w", err)
	}

	rsaKey, ok := parsedKey.(*rsa.PrivateKey)
	if !ok {
		return "", "", fmt.Errorf("private key ไม่ใช่ RSA")
	}

	now := time.Now().Unix()
	exp := now + 3600

	headerJSON, _ := json.Marshal(map[string]string{"alg": "RS256", "typ": "JWT"})
	claimJSON, _ := json.Marshal(map[string]interface{}{
		"iss":   sa.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   "https://oauth2.googleapis.com/token",
		"iat":   now,
		"exp":   exp,
	})

	encodedHeader := base64.RawURLEncoding.EncodeToString(headerJSON)
	encodedClaim := base64.RawURLEncoding.EncodeToString(claimJSON)
	unsignedJWT := encodedHeader + "." + encodedClaim

	h := sha256.New()
	h.Write([]byte(unsignedJWT))
	signature, err := rsa.SignPKCS1v15(rand.Reader, rsaKey, crypto.SHA256, h.Sum(nil))
	if err != nil {
		return "", "", fmt.Errorf("เซ็น JWT error: %w", err)
	}

	signedJWT := unsignedJWT + "." + base64.RawURLEncoding.EncodeToString(signature)

	// แลก Access Token จาก Google OAuth2
	resp, err := http.PostForm("https://oauth2.googleapis.com/token", map[string][]string{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {signedJWT},
	})
	if err != nil {
		return "", "", fmt.Errorf("ขอ OAuth2 token error: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("Google OAuth2 error (%d): %s", resp.StatusCode, string(body))
	}

	var tokenResp struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", "", err
	}

	cachedToken = tokenResp.AccessToken
	tokenExpiry = time.Now().Add(time.Duration(tokenResp.ExpiresIn-60) * time.Second)

	return cachedToken, sa.ProjectID, nil
}

// SendChatPush ส่ง FCM push notification สำหรับข้อความแชทใหม่ผ่าน FCM HTTP v1 (Non-blocking Fast Response)
func (h *PushHandler) SendChatPush(c *gin.Context) {

	var req SendChatPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ครบถ้วน: " + err.Error()})
		return
	}

	// ตอบกลับ 200 OK ให้ Client ทันทีแบบ 0ms ไม่ต้องรอ Network Roundtrip ของ FCM
	c.JSON(http.StatusOK, gin.H{"status": "queued"})

	// ประมวลผลและยิง Push Notification ใน Background Goroutine
	go func(r SendChatPushRequest) {
		fcmToken, err := h.getReceiverFCMToken(r.ReceiverID)
		if err != nil || fcmToken == "" {
			log.Printf("ไม่พบ FCM token ของ receiver %s: %v", r.ReceiverID, err)
			return
		}

		err = sendFCMv1ChatPush(fcmToken, r)
		if err != nil {
			log.Printf("ส่ง FCM chat push ล้มเหลว: %v", err)
			if strings.Contains(err.Error(), "UNREGISTERED") ||
				strings.Contains(err.Error(), "NotRegistered") ||
				strings.Contains(err.Error(), "404") {
				h.deleteReceiverFCMToken(r.ReceiverID)
			}
		}
	}(req)
}

// deleteReceiverFCMToken ล้าง token ที่หมดอายุ/ใช้งานไม่ได้ออกจาก cache และ Supabase
func (h *PushHandler) deleteReceiverFCMToken(receiverID string) {
	fcmTokenCache.Delete(receiverID)

	sbURL := os.Getenv("SUPABASE_URL")
	sbKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")
	if sbURL == "" || sbKey == "" {
		return
	}

	url := fmt.Sprintf("%s/rest/v1/profile_tb?user_id=eq.%s",
		strings.TrimRight(sbURL, "/"), receiverID)

	req, err := http.NewRequest("PATCH", url, bytes.NewBuffer([]byte(`{"fcm_token":null}`)))
	if err != nil {
		return
	}
	req.Header.Set("apikey", sbKey)
	req.Header.Set("Authorization", "Bearer "+sbKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=minimal")

	resp, err := pushHttpClient.Do(req)
	if err == nil && resp != nil {
		resp.Body.Close()
		log.Printf("ล้าง FCM token ที่หมดอายุ (UNREGISTERED) ของ receiver %s เรียบร้อยแล้ว", receiverID)
	}
}

// getReceiverFCMToken ดึง fcm_token จาก profile_tb โดยใช้ Cache หรือ REST API พร้อม Timeout
func (h *PushHandler) getReceiverFCMToken(receiverID string) (string, error) {
	if val, ok := fcmTokenCache.Load(receiverID); ok {
		cached := val.(fcmCachedToken)
		if time.Now().Before(cached.expiresAt) {
			return cached.token, nil
		}
	}

	sbURL := os.Getenv("SUPABASE_URL")
	sbKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")

	if sbURL == "" || sbKey == "" {
		return "", fmt.Errorf("SUPABASE_URL หรือ SUPABASE_SERVICE_ROLE_KEY ไม่ได้ตั้งค่า")
	}

	url := fmt.Sprintf("%s/rest/v1/profile_tb?select=fcm_token&user_id=eq.%s&limit=1",
		strings.TrimRight(sbURL, "/"), receiverID)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", err
	}

	req.Header.Set("apikey", sbKey)
	req.Header.Set("Authorization", "Bearer "+sbKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := pushHttpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var rows []map[string]interface{}
	if err := json.Unmarshal(body, &rows); err != nil {
		return "", err
	}

	if len(rows) == 0 {
		return "", nil
	}

	token, _ := rows[0]["fcm_token"].(string)
	if token != "" {
		fcmTokenCache.Store(receiverID, fcmCachedToken{
			token:     token,
			expiresAt: time.Now().Add(5 * time.Minute),
		})
	}
	return token, nil
}

// extractCleanChatMessage สกัดเอาเฉพาะข้อความจริง ตัดคำนำหน้าตอบกลับ (↩ ตอบกลับ:...) ออก
func extractCleanChatMessage(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "↩ ตอบกลับ:") || strings.HasPrefix(raw, "💬 ตอบกลับ") || strings.HasPrefix(raw, "↪ ตอบกลับ") {
		if newlineIdx := strings.Index(raw, "\n"); newlineIdx != -1 {
			actual := strings.TrimSpace(raw[newlineIdx+1:])
			if actual != "" {
				return actual
			}
		}
		parts := strings.Split(raw, "|")
		if len(parts) >= 2 {
			actual := strings.TrimSpace(parts[1])
			if actual != "" {
				return actual
			}
		}
	}
	return raw
}

// sendFCMv1ChatPush ส่ง push notification ข้อความแชทผ่าน FCM HTTP v1
func sendFCMv1ChatPush(token string, req SendChatPushRequest) error {

	senderName := req.SenderName
	if senderName == "" {
		senderName = "ข้อความใหม่"
	}
	bodyMsg := extractCleanChatMessage(req.Message)
	if bodyMsg == "" {
		bodyMsg = "ส่งข้อความถึงคุณ"
	}

	oauthToken, projectID, err := getGoogleOAuth2Token()
	if err != nil {
		return err
	}

	payload := map[string]interface{}{
		"message": map[string]interface{}{
			"token": token,
			"notification": map[string]string{
				"title": senderName,
				"body":  bodyMsg,
			},
			"data": map[string]string{
				"type":            "chat_message",
				"conversation_id": req.ConversationID,
				"message_id":      req.MessageID,
				"sender_name":     senderName,
				"sender_avatar":   req.SenderAvatar,
				"message":         bodyMsg,
				"title":           senderName,
				"body":            bodyMsg,
			},
			"android": map[string]interface{}{
				"priority": "HIGH",
				"notification": map[string]interface{}{
					"channel_id":   "yuemnoi_chat_messages_v3",
					"title":        senderName,
					"body":         bodyMsg,
					"sound":        "message_tone",
					"click_action": "FLUTTER_NOTIFICATION_CLICK",
				},
			},
			"apns": map[string]interface{}{
				"headers": map[string]string{
					"apns-priority": "10",
				},
				"payload": map[string]interface{}{
					"aps": map[string]interface{}{
						"alert": map[string]string{
							"title": senderName,
							"body":  bodyMsg,
						},
						"badge":             1,
						"sound":             "message_tone.wav",
						"content-available": 1,
					},
				},
			},
		},
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+oauthToken)

	resp, err := pushHttpClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("FCM v1 chat push responded with status %d: %s", resp.StatusCode, string(respBody))
	}

	log.Printf("FCM v1 chat push sent successfully to receiver: %s", req.ReceiverID)
	return nil
}




