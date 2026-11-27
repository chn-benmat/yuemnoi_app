package supabase

import (
	"context"
	"fmt"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
)

type supabaseConversationContactRepository struct {
	client *supabase.Client
}

type conversationParticipants struct {
	RenterID string `json:"renter_id"`
	OwnerID  string `json:"owner_id"`
}

func NewSupabaseConversationContactRepository(
	client *supabase.Client,
) domain.ConversationContactRepository {
	return &supabaseConversationContactRepository{client: client}
}

func (r *supabaseConversationContactRepository) PhoneForConversation(
	ctx context.Context,
	requesterID string,
	conversationID string,
) (string, error) {
	var conversations []conversationParticipants
	err := schemaDatabase(r.client, messagingSchema).From("conversation_tb").
		Select("renter_id,owner_id").
		Eq("id", conversationID).
		ExecuteWithContext(ctx, &conversations)
	if err != nil {
		return "", fmt.Errorf("load conversation participants: %w", err)
	}
	if len(conversations) == 0 {
		return "", domain.ErrConversationNotFound
	}

	conversation := conversations[0]
	var contactUserID string
	switch requesterID {
	case conversation.RenterID:
		contactUserID = conversation.OwnerID
	case conversation.OwnerID:
		contactUserID = conversation.RenterID
	default:
		return "", domain.ErrContactForbidden
	}
	if contactUserID == "" {
		return "", domain.ErrContactPhoneNotFound
	}

	user, err := r.client.Admin.GetUser(ctx, contactUserID)
	if err != nil {
		return "", fmt.Errorf("load conversation contact user: %w", err)
	}
	if user.AppMetaData["account_delete_after"] != nil {
		return "", domain.ErrContactForbidden
	}

	phone := ""
	if metadataPhone, ok := user.UserMetaData["phone"].(string); ok {
		phone = strings.TrimSpace(metadataPhone)
	}
	if phone == "" {
		phone = strings.TrimSpace(user.Phone)
	}
	if phone == "" {
		return "", domain.ErrContactPhoneNotFound
	}

	return phone, nil
}
