package fcm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/auth/credentials"
	"cloud.google.com/go/auth/httptransport"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/jellydator/ttlcache/v3"
	"google.golang.org/api/option"
)

const pushTimeout = 10 * time.Second

// TokenManager จัดการการอ่านและลบ FCM Token ของผู้ใช้จากฐานข้อมูล
type TokenManager interface {
	GetFCMToken(ctx context.Context, userID string) (string, error)
	DeleteFCMToken(ctx context.Context, userID string) error
}

const receiverTokenTTL = 5 * time.Minute

// FCMSender ส่งแจ้งเตือนผ่าน Firebase Admin SDK และแคช device token ชั่วคราว
type FCMSender struct {
	tokenManager  TokenManager
	client        MessageClient
	fcmTokenCache *ttlcache.Cache[string, string]
}

// MessageClient เป็นขอบเขตสำหรับส่งข้อความผ่าน Firebase SDK หรือ client ที่ฉีดเข้ามา
type MessageClient interface {
	Send(context.Context, *messaging.Message) (string, error)
}

// เส้นทางใหม่ส่งไปยัง token ของงานที่ถูก claim โดยไม่อ่านหรือแก้ token ของบัญชีอื่น
func (s *FCMSender) SendNotification(ctx context.Context, delivery domain.NotificationDelivery) error {
	if s == nil || s.client == nil {
		return errors.New("Firebase messaging is not configured")
	}
	if strings.TrimSpace(delivery.Token) == "" {
		return domain.ErrPushTokenUnregistered
	}
	if !delivery.ExpiresAt.IsZero() && !delivery.ExpiresAt.After(time.Now()) {
		return domain.ErrPushExpired
	}
	ctx, cancel := context.WithTimeout(ctx, pushTimeout)
	defer cancel()
	_, err := s.client.Send(ctx, buildNotificationMessage(delivery))
	if messaging.IsUnregistered(err) {
		return domain.ErrPushTokenUnregistered
	}
	if messaging.IsInvalidArgument(err) {
		return domain.ErrPushPermanent
	}
	return err
}

func buildNotificationMessage(delivery domain.NotificationDelivery) *messaging.Message {
	n := delivery.Payload
	if n.ID == "" {
		n.ID = delivery.NotificationID
	}
	title, body := notificationText(n.Title, 180), notificationText(n.Body, 700)
	if title == "" {
		title = "Yuemnoi"
	}
	if body == "" {
		body = "คุณมีการแจ้งเตือนใหม่"
	}
	channelID := "yuemnoi_app_updates_v1"
	tag := n.ID
	if n.Category == "chat" {
		channelID = "yuemnoi_chat_messages_v3"
		if n.ConversationID != "" {
			tag = "chat_" + n.ConversationID
		}
	} else if n.Category == "rental" {
		channelID = "yuemnoi_rental_updates_v1"
	}
	data := map[string]string{
		"notification_id": n.ID, "recipient_id": delivery.UserID, "category": n.Category, "type": n.Type,
		"title": title, "body": body, "event_key": n.EventKey,
		"conversation_id": n.ConversationID, "unread_count": strconv.Itoa(n.UnreadCount),
	}
	if n.BookingID != nil {
		data["booking_id"] = strconv.FormatInt(*n.BookingID, 10)
	}
	if n.ItemID != nil {
		data["item_id"] = strconv.FormatInt(*n.ItemID, 10)
	}
	if !n.UpdatedAt.IsZero() {
		data["updated_at"] = n.UpdatedAt.UTC().Format(time.RFC3339Nano)
	}
	for _, key := range []string{"message_id", "sender_name", "sender_avatar"} {
		if value, ok := n.Data[key].(string); ok {
			data[key] = notificationText(value, 300)
		}
	}
	if data["event_key"] == "" {
		data["event_key"] = n.ID
	}
	for _, key := range []string{"event_key", "event_at", "destination", "message_id"} {
		if value := notificationScalar(n.Data[key]); value != "" {
			data[key] = notificationText(value, 200)
		}
	}
	if data["event_at"] == "" {
		data["event_at"] = data["updated_at"]
	}
	expiresAt := delivery.ExpiresAt
	if expiresAt.IsZero() {
		expiresAt = time.Now().UTC().Add(24 * time.Hour)
	}
	ttl := time.Until(expiresAt)
	if ttl < 0 {
		ttl = 0
	}
	if ttl > 28*24*time.Hour {
		ttl = 28 * 24 * time.Hour
	}
	data["expires_at"] = expiresAt.UTC().Format(time.RFC3339Nano)
	return &messaging.Message{
		Token:        delivery.Token,
		Notification: &messaging.Notification{Title: title, Body: body},
		Data:         data,
		Android: &messaging.AndroidConfig{
			Priority:     "high",
			TTL:          &ttl,
			Notification: &messaging.AndroidNotification{ChannelID: channelID, Sound: "message_tone", Tag: tag},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{"apns-priority": "10", "apns-collapse-id": tag, "apns-expiration": strconv.FormatInt(expiresAt.Unix(), 10)},
			Payload: &messaging.APNSPayload{Aps: &messaging.Aps{Sound: "message_tone.wav", ThreadID: tag}},
		},
	}
}

func notificationScalar(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case json.Number:
		return v.String()
	case int64:
		return strconv.FormatInt(v, 10)
	case int:
		return strconv.Itoa(v)
	default:
		return ""
	}
}

func notificationText(value string, maxBytes int) string {
	value = strings.TrimSpace(value)
	if len(value) <= maxBytes {
		return value
	}
	end := maxBytes - len("…")
	for end > 0 && !utf8.RuneStart(value[end]) {
		end--
	}
	return value[:end] + "…"
}

// NewReceiverTokenCache ใช้นโยบายอายุคงที่ร่วมกันทั้งการประกอบจริงและ client ที่ฉีดเข้ามา
func NewReceiverTokenCache() *ttlcache.Cache[string, string] {
	return ttlcache.New[string, string](
		ttlcache.WithTTL[string, string](receiverTokenTTL),
		ttlcache.WithDisableTouchOnHit[string, string](),
	)
}

// NewFCMSenderWithClient รับ client และ cache ที่ผู้เรียกจัดการ เพื่อแทนบริการภายนอกได้
func NewFCMSenderWithClient(tokenManager TokenManager, client MessageClient, cache *ttlcache.Cache[string, string]) *FCMSender {
	if cache == nil {
		cache = NewReceiverTokenCache()
	}
	return &FCMSender{tokenManager: tokenManager, client: client, fcmTokenCache: cache}
}

// NewFCMSender ใช้ไลบรารีของ Google จัดการ credentials การเซ็น JWT และ OAuth
// คืน sender ที่ยังเรียกใช้งานได้พร้อม error เมื่อไม่มี credentials เพื่อให้ server เริ่มได้
func NewFCMSender(tokenManager TokenManager, saPath, saJSON string, httpClient *http.Client) (*FCMSender, error) {
	sender := NewFCMSenderWithClient(tokenManager, nil, nil)
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
	if s.fcmTokenCache != nil {
		// ใช้ lazy eviction เพื่อไม่สร้าง goroutine และให้ฐานข้อมูลเป็นแหล่งข้อมูลหลักหลังครบ TTL
		s.fcmTokenCache.DeleteExpired()
		if cached := s.fcmTokenCache.Get(receiverID); cached != nil {
			return cached.Value(), nil
		}
	}
	if s.tokenManager == nil {
		return "", fmt.Errorf("token manager is not configured")
	}
	token, err := s.tokenManager.GetFCMToken(ctx, receiverID)
	if err != nil {
		return "", err
	}
	if token != "" && s.fcmTokenCache != nil {
		s.fcmTokenCache.Set(receiverID, token, ttlcache.DefaultTTL)
	}
	return token, nil
}

// invalidateReceiverToken ลบ token ที่หมดอายุออกจาก cache และฐานข้อมูล
func (s *FCMSender) invalidateReceiverToken(ctx context.Context, receiverID string) {
	if s.fcmTokenCache != nil {
		s.fcmTokenCache.Delete(receiverID)
	}
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
