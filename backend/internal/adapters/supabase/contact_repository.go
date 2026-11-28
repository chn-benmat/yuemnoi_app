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

	// เบอร์ติดต่อของแอปเก็บที่ profile_tb.phone เพียงที่เดียว
	var profiles []struct {
		Phone *string `json:"phone"`
	}
	err = schemaDatabase(r.client, profilesSchema).From("profile_tb").
		Select("phone").
		Eq("user_id", contactUserID).
		ExecuteWithContext(ctx, &profiles)
	if err != nil {
		return "", fmt.Errorf("load conversation contact phone: %w", err)
	}
	if len(profiles) == 0 || profiles[0].Phone == nil || strings.TrimSpace(*profiles[0].Phone) == "" {
		return "", domain.ErrContactPhoneNotFound
	}

	return strings.TrimSpace(*profiles[0].Phone), nil
}
