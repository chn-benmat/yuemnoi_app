package domain

import "context"

type RentalQueueRequest struct {
	Action         string
	ConversationID string
	ItemID         int64
	MessageID      int64
}

type RentalQueueItem struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type RentalQueueResult struct {
	Items     []RentalQueueItem `json:"items,omitempty"`
	MessageID int64             `json:"message_id,omitempty"`
}

type RentalQueueRepository interface {
	RentalQueue(ctx context.Context, actor string, request RentalQueueRequest) (RentalQueueResult, error)
}

type RentalReceiptPauseRepository interface {
	ConfirmRentalReceiptWithPause(ctx context.Context, actor string, id int64) (*RentalOrder, error)
}
