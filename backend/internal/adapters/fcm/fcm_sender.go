package fcm

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/auth/credentials"
	"cloud.google.com/go/auth/httptransport"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"google.golang.org/api/option"
)

const pushTimeout = 10 * time.Second

// TokenManager จัดการการอ่านและลบ FCM Token ของผู้ใช้จากฐานข้อมูล
type TokenManager interface {
	GetFCMToken(ctx context.Context, userID string) (string, error)
	DeleteFCMToken(ctx context.Context, userID string) error
}

type fcmCachedToken struct {
	token     string
	expiresAt time.Time
}

// FCMSender ส่งแจ้งเตือนผ่าน Firebase Admin SDK และแคช device token ชั่วคราว
type FCMSender struct {
	tokenManager  TokenManager
	client        *messaging.Client
	fcmTokenCache sync.Map
}

// NewFCMSender ใช้ไลบรารีของ Google จัดการ credentials การเซ็น JWT และ OAuth
// คืน sender ที่ยังเรียกใช้งานได้พร้อม error เมื่อไม่มี credentials เพื่อให้ server เริ่มได้
func NewFCMSender(tokenManager TokenManager, saPath, saJSON string, httpClient *http.Client) (*FCMSender, error) {
	sender := &FCMSender{tokenManager: tokenManager}
	data, err := loadServiceAccount(saPath, saJSON)
	if err != nil {
		return sender, err
	}
	var account struct {
		Type      string `json:"type"`
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(data, &account); err != nil {
		return sender, fmt.Errorf("invalid Firebase service account JSON: %w", err)
	}
	if account.Type != "service_account" || strings.TrimSpace(account.ProjectID) == "" {
		return sender, fmt.Errorf("Firebase service account requires type service_account and project_id")
	}
	baseClient := http.Client{Timeout: pushTimeout}
	if httpClient != nil {
		baseClient = *httpClient
		if baseClient.Timeout <= 0 {
			baseClient.Timeout = pushTimeout
		}
	}
	baseTransport := baseClient.Transport
	if baseTransport == nil {
		baseTransport = http.DefaultTransport
		if standard, ok := baseTransport.(*http.Transport); ok && httpClient == nil {
			pool := standard.Clone()
			pool.MaxIdleConns = 100
			pool.MaxIdleConnsPerHost = 20
			baseTransport = pool
		}
	}
	baseClient.Transport = baseTransport
	// ใช้ request context ทั้งตอนแลก OAuth token และตอนส่ง FCM เพื่อยกเลิกได้ทันที
	authClient, err := httptransport.NewClient(&httptransport.Options{
		BaseRoundTripper: baseTransport,
		DetectOpts: &credentials.DetectOptions{
			CredentialsJSON:     data,
			Scopes:              []string{"https://www.googleapis.com/auth/firebase.messaging"},
			Client:              &baseClient,
			DisableAsyncRefresh: true,
		},
	})
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase credentials: %w", err)
	}
	// แยก client สำหรับ FCM ออกจาก client แลก token เพื่อไม่ให้ transport เรียกตัวเอง
	messagingHTTPClient := baseClient
	messagingHTTPClient.Transport = authClient.Transport
	app, err := firebase.NewApp(context.Background(), &firebase.Config{ProjectID: account.ProjectID}, option.WithHTTPClient(&messagingHTTPClient))
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase app: %w", err)
	}
	sender.client, err = app.Messaging(context.Background())
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase messaging: %w", err)
	}
	return sender, nil
}

// ExtractCleanChatMessage สกัดเฉพาะข้อความจริงและตัดคำนำหน้าตอบกลับ
func ExtractCleanChatMessage(raw string) string {
	return extractCleanChatMessage(raw)
}

// SendChatPush คงรูปแบบแจ้งเตือนเดิมและลบเฉพาะ token ที่ FCM ยืนยันว่าเลิกลงทะเบียนแล้ว
func (s *FCMSender) SendChatPush(ctx context.Context, n domain.ChatPushNotification) error {
	ctx, cancel := context.WithTimeout(ctx, pushTimeout)
	defer cancel()
	if s.client == nil {
		return fmt.Errorf("Firebase messaging is not configured")
	}
	token, err := s.getReceiverToken(ctx, n.ReceiverID)
	if err != nil {
		return fmt.Errorf("receiver fcm token not found: %w", err)
	}
	if token == "" {
		return fmt.Errorf("receiver fcm token not found")
	}
	err = s.sendFCMv1(ctx, token, n)
	if err != nil {
		if messaging.IsUnregistered(err) {
			s.invalidateReceiverToken(ctx, n.ReceiverID)
		}
		return fmt.Errorf("send FCM chat push: %w", err)
	}
	return nil
}

// getReceiverToken ดึง token จาก cache หรือฐานข้อมูลผ่าน TokenManager
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
		s.fcmTokenCache.Store(receiverID, fcmCachedToken{token, time.Now().Add(5 * time.Minute)})
	}
	return token, nil
}

// invalidateReceiverToken ลบ token ที่หมดอายุออกจาก cache และฐานข้อมูล
func (s *FCMSender) invalidateReceiverToken(ctx context.Context, receiverID string) {
	s.fcmTokenCache.Delete(receiverID)
	if s.tokenManager != nil {
		if err := s.tokenManager.DeleteFCMToken(ctx, receiverID); err != nil {
			slog.Warn("ล้าง FCM token ที่หมดอายุไม่สำเร็จ")
		}
	}
}

// sendFCMv1 ใช้โครงสร้างของ SDK โดยคง data เสียง และ channel ของ Flutter เดิม
func (s *FCMSender) sendFCMv1(ctx context.Context, token string, req domain.ChatPushNotification) error {
	senderName := strings.TrimSpace(req.SenderName)
	if senderName == "" {
		senderName = "ข้อความใหม่"
	}
	body := extractCleanChatMessage(req.Message)
	if body == "" {
		body = "ส่งข้อความถึงคุณ"
	}
	badge := 1
	_, err := s.client.Send(ctx, &messaging.Message{
		Token:        token,
		Notification: &messaging.Notification{Title: senderName, Body: body},
		Data: map[string]string{
			"type": "chat_message", "conversation_id": req.ConversationID, "message_id": req.MessageID,
			"sender_name": senderName, "sender_avatar": req.SenderAvatar, "message": body,
			"title": senderName, "body": body,
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				ChannelID: "yuemnoi_chat_messages_v3", Title: senderName, Body: body,
				Sound: "message_tone", ClickAction: "FLUTTER_NOTIFICATION_CLICK",
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{"apns-priority": "10"},
			Payload: &messaging.APNSPayload{Aps: &messaging.Aps{
				Alert: &messaging.ApsAlert{Title: senderName, Body: body}, Badge: &badge,
				Sound: "message_tone.wav", ContentAvailable: true,
			}},
		},
	})
	return err
}

// loadServiceAccount รองรับ JSON และตำแหน่งไฟล์ที่ระบบเดิมใช้งาน
func loadServiceAccount(saPath, saJSON string) ([]byte, error) {
	if saJSON != "" {
		return []byte(saJSON), nil
	}
	candidates := []string{"service-account.json", "backend/service-account.json", "../service-account.json"}
	if saPath != "" {
		candidates = append([]string{saPath}, candidates...)
	} else {
		files, _ := filepath.Glob("*.json")
		candidates = append(candidates, files...)
	}
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err == nil && (saPath != "" || (strings.Contains(string(data), "private_key") && strings.Contains(string(data), "client_email"))) {
			return data, nil
		}
	}
	return nil, fmt.Errorf("Firebase service account is not available")
}

// extractCleanChatMessage สกัดเฉพาะข้อความจริงและตัดคำนำหน้าตอบกลับ
func extractCleanChatMessage(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "↩ ตอบกลับ:") || strings.HasPrefix(raw, "💬 ตอบกลับ") || strings.HasPrefix(raw, "↪ ตอบกลับ") {
		if newlineIdx := strings.Index(raw, "\n"); newlineIdx != -1 {
			if actual := strings.TrimSpace(raw[newlineIdx+1:]); actual != "" {
				return actual
			}
		}
		if parts := strings.Split(raw, "|"); len(parts) >= 2 {
			if actual := strings.TrimSpace(parts[1]); actual != "" {
				return actual
			}
		}
	}
	return raw
}
