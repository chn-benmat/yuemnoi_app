package fcm

import (
	"bytes"
	"context"
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
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

// TokenManager จัดการการอ่านและลบ FCM Token ของผู้ใช้จากฐานข้อมูล
type TokenManager interface {
	GetFCMToken(ctx context.Context, userID string) (string, error)
	DeleteFCMToken(ctx context.Context, userID string) error
}

// ServiceAccountKey โครงสร้างไฟล์ Service Account JSON ของ Google Cloud / Firebase
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

type fcmCachedToken struct {
	token     string
	expiresAt time.Time
}

// FCMSender ทำหน้าที่เป็น Adapter ส่ง Push Notification ผ่าน Firebase Cloud Messaging HTTP v1
type FCMSender struct {
	tokenManager   TokenManager
	httpClient     *http.Client
	fcmEndpoint    string
	oauthEndpoint  string
	saKey          *ServiceAccountKey
	tokenMu        sync.Mutex
	cachedOAuth    string
	oauthExpiresAt time.Time
	fcmTokenCache  sync.Map
}

// NewFCMSender สร้างอินสแตนซ์ของ FCMSender สำหรับส่ง Push Notification
func NewFCMSender(tokenManager TokenManager, saPath, saJSON string, httpClient *http.Client) (*FCMSender, error) {
	if httpClient == nil {
		httpClient = &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 20,
				IdleConnTimeout:     90 * time.Second,
			},
		}
	}

	sa, err := loadServiceAccount(saPath, saJSON)
	if err != nil {
		slog.Warn("ไม่สามารถโหลด Firebase Service Account (ฟังก์ชัน Push จะยังไม่สามารถส่งจริงได้)", slog.Any("error", err))
	}

	return &FCMSender{
		tokenManager:  tokenManager,
		httpClient:    httpClient,
		oauthEndpoint: "https://oauth2.googleapis.com/token",
		saKey:         sa,
	}, nil
}

// SetEndpointsForTesting ใช้สำหรับกำหนด Mock Endpoints ในการทดสอบ
func (s *FCMSender) SetEndpointsForTesting(oauthEndpoint, fcmEndpoint string) {
	s.oauthEndpoint = oauthEndpoint
	s.fcmEndpoint = fcmEndpoint
}

// SetServiceAccountForTesting ใช้สำหรับกำหนด Mock Service Account ในการทดสอบ
func (s *FCMSender) SetServiceAccountForTesting(sa *ServiceAccountKey) {
	s.saKey = sa
}

// ExtractCleanChatMessage สกัดเอาเฉพาะข้อความจริง ตัดคำนำหน้าตอบกลับ
func ExtractCleanChatMessage(raw string) string {
	return extractCleanChatMessage(raw)
}

// SendChatPush ดำเนินการค้นหา FCM Token และส่ง Notification ไปยังผู้รับ
func (s *FCMSender) SendChatPush(ctx context.Context, n domain.ChatPushNotification) error {
	fcmToken, err := s.getReceiverToken(ctx, n.ReceiverID)
	if err != nil || fcmToken == "" {
		return fmt.Errorf("receiver fcm token not found: %w", err)
	}

	err = s.sendFCMv1(ctx, fcmToken, n)
	if err != nil {
		slog.Error("ส่ง FCM chat push ล้มเหลว", slog.String("receiver_id", n.ReceiverID), slog.Any("error", err))
		if strings.Contains(err.Error(), "UNREGISTERED") ||
			strings.Contains(err.Error(), "NotRegistered") ||
			strings.Contains(err.Error(), "404") {
			s.invalidateReceiverToken(ctx, n.ReceiverID)
		}
		return err
	}

	return nil
}

// getReceiverToken ดึง token จาก cache หรือจากฐานข้อมูลผ่าน TokenManager
func (s *FCMSender) getReceiverToken(ctx context.Context, receiverID string) (string, error) {
	if val, ok := s.fcmTokenCache.Load(receiverID); ok {
		cached := val.(fcmCachedToken)
		if time.Now().Before(cached.expiresAt) {
			return cached.token, nil
		}
	}

	if s.tokenManager == nil {
		return "", fmt.Errorf("token manager is not configured")
	}

	token, err := s.tokenManager.GetFCMToken(ctx, receiverID)
	if err != nil {
		return "", err
	}

	if token != "" {
		s.fcmTokenCache.Store(receiverID, fcmCachedToken{
			token:     token,
			expiresAt: time.Now().Add(5 * time.Minute),
		})
	}
	return token, nil
}

// invalidateReceiverToken ลบ Token ที่หมดอายุออกจาก cache และฐานข้อมูล
func (s *FCMSender) invalidateReceiverToken(ctx context.Context, receiverID string) {
	s.fcmTokenCache.Delete(receiverID)
	if s.tokenManager != nil {
		_ = s.tokenManager.DeleteFCMToken(ctx, receiverID)
		slog.Info("ล้าง FCM token ที่หมดอายุ (UNREGISTERED) เรียบร้อยแล้ว", slog.String("receiver_id", receiverID))
	}
}

// sendFCMv1 จัดเตรียม Payload และยิง HTTP POST ไปยัง FCM HTTP v1 API
func (s *FCMSender) sendFCMv1(ctx context.Context, token string, req domain.ChatPushNotification) error {
	senderName := strings.TrimSpace(req.SenderName)
	if senderName == "" {
		senderName = "ข้อความใหม่"
	}
	bodyMsg := extractCleanChatMessage(req.Message)
	if bodyMsg == "" {
		bodyMsg = "ส่งข้อความถึงคุณ"
	}

	oauthToken, projectID, err := s.getOAuth2Token(ctx)
	if err != nil {
		return fmt.Errorf("get google oauth token failed: %w", err)
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

	endpoint := s.fcmEndpoint
	if endpoint == "" {
		endpoint = fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+oauthToken)

	resp, err := s.httpClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("FCM v1 chat push responded with status %d: %s", resp.StatusCode, string(respBody))
	}

	slog.Info("FCM v1 chat push sent successfully", slog.String("receiver_id", req.ReceiverID))
	return nil
}

// getOAuth2Token สร้างและแคช OAuth2 Access Token สำหรับ FCM v1 API
func (s *FCMSender) getOAuth2Token(ctx context.Context) (string, string, error) {
	s.tokenMu.Lock()
	defer s.tokenMu.Unlock()

	if s.saKey == nil {
		return "", "", fmt.Errorf("firebase service account is not loaded")
	}

	if s.cachedOAuth != "" && time.Now().Before(s.oauthExpiresAt) {
		return s.cachedOAuth, s.saKey.ProjectID, nil
	}

	block, _ := pem.Decode([]byte(s.saKey.PrivateKey))
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
		"iss":   s.saKey.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   s.oauthEndpoint,
		"iat":   now,
		"exp":   exp,
	})

	unsignedJWT := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimJSON)
	h := sha256.New()
	h.Write([]byte(unsignedJWT))
	signature, err := rsa.SignPKCS1v15(rand.Reader, rsaKey, crypto.SHA256, h.Sum(nil))
	if err != nil {
		return "", "", fmt.Errorf("เซ็น JWT error: %w", err)
	}

	signedJWT := unsignedJWT + "." + base64.RawURLEncoding.EncodeToString(signature)

	reqBody := strings.NewReader(fmt.Sprintf(
		"grant_type=%s&assertion=%s",
		"urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer",
		signedJWT,
	))

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, s.oauthEndpoint, reqBody)
	if err != nil {
		return "", "", fmt.Errorf("ขอ OAuth2 token error: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.httpClient.Do(httpReq)
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

	s.cachedOAuth = tokenResp.AccessToken
	s.oauthExpiresAt = time.Now().Add(time.Duration(tokenResp.ExpiresIn-60) * time.Second)

	return s.cachedOAuth, s.saKey.ProjectID, nil
}

// loadServiceAccount โหลด Service Account จาก JSON หรือจากไฟล์ Path
func loadServiceAccount(saPath, saJSON string) (*ServiceAccountKey, error) {
	var data []byte
	var err error

	if saJSON != "" {
		data = []byte(saJSON)
	} else if saPath != "" {
		data, err = os.ReadFile(saPath)
		if err != nil {
			for _, candidate := range []string{saPath, "service-account.json", "backend/service-account.json", "../service-account.json"} {
				if d, e := os.ReadFile(candidate); e == nil {
					data = d
					break
				}
			}
			if len(data) == 0 {
				return nil, fmt.Errorf("ไม่สามารถอ่านไฟล์ Service Account Path: %w", err)
			}
		}
	} else {
		candidates := []string{"service-account.json", "backend/service-account.json", "../service-account.json"}
		files, _ := filepath.Glob("*.json")
		candidates = append(candidates, files...)

		for _, f := range candidates {
			d, err := os.ReadFile(f)
			if err == nil && strings.Contains(string(d), "private_key") && strings.Contains(string(d), "client_email") {
				data = d
				slog.Info("พบ Firebase Service Account อัตโนมัติ", slog.String("file", f))
				break
			}
		}
	}

	if len(data) == 0 {
		return nil, fmt.Errorf("ไม่พบ Firebase Service Account ข้อมูล")
	}

	var sa ServiceAccountKey
	if err := json.Unmarshal(data, &sa); err != nil {
		return nil, fmt.Errorf("รูปแบบ Service Account JSON ไม่ถูกต้อง: %w", err)
	}

	return &sa, nil
}

// extractCleanChatMessage สกัดเอาเฉพาะข้อความจริง ตัดคำนำหน้าตอบกลับ
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
