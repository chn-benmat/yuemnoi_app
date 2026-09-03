package domain

import (
	"context"
	"errors"
)

var (
	ErrConversationNotFound = errors.New("conversation not found")
	ErrContactForbidden     = errors.New("conversation contact is forbidden")
	ErrContactPhoneNotFound = errors.New("contact phone not found")
)

type ConversationContactRepository interface {
	PhoneForConversation(
		ctx context.Context,
		requesterID string,
		conversationID string,
	) (string, error)
}
