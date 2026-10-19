package supabase

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseUserRepository) NotificationRepository() domain.NotificationRepository {
	return NewSupabaseNotificationRepository(r.client)
}

func (r *supabaseUserRepository) registerLegacyFCMToken(ctx context.Context, userID, token string) error {
	token = strings.TrimSpace(token)
	key := sha256.Sum256([]byte(token))
	return r.NotificationRepository().RegisterNotificationDevice(ctx, userID, domain.NotificationDevice{
		InstallationID: fmt.Sprintf("legacy-%x", key), Token: token, Platform: "android",
	})
}

func (r *supabaseUserRepository) ValidateChatPush(ctx context.Context, senderID string, n domain.ChatPushNotification) error {
	var messages []struct {
		ConversationID string `json:"conversation_id"`
		SenderID       string `json:"sender_id"`
	}
	if err := r.client.DB.From("chat_message_tb").Select("conversation_id,sender_id").Eq("id", n.MessageID).ExecuteWithContext(ctx, &messages); err != nil {
		return fmt.Errorf("load push message: %w", err)
	}
	if len(messages) != 1 || messages[0].SenderID != senderID || messages[0].ConversationID != n.ConversationID {
		return domain.ErrNotificationForbidden
	}
	var conversations []struct {
		RenterID string `json:"renter_id"`
		OwnerID  string `json:"owner_id"`
	}
	if err := r.client.DB.From("conversation_tb").Select("renter_id,owner_id").Eq("id", n.ConversationID).ExecuteWithContext(ctx, &conversations); err != nil {
		return fmt.Errorf("load push conversation: %w", err)
	}
	if len(conversations) != 1 {
		return domain.ErrNotificationForbidden
	}
	c := conversations[0]
	if (senderID == c.RenterID && n.ReceiverID == c.OwnerID) || (senderID == c.OwnerID && n.ReceiverID == c.RenterID) {
		return nil
	}
	return domain.ErrNotificationForbidden
}
