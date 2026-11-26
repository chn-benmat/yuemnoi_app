package supabase

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
)

type accountDeletionRepository struct {
	rpc     domain.OperationsStore
	storage *storageClient
}

func NewAccountDeletionRepository(client *supabase.Client, serviceKey string) domain.AccountDeletionRepository {
	return &accountDeletionRepository{
		rpc: NewOperationsRepository(client.BaseURL, serviceKey), storage: newStorageClient(client, serviceKey),
	}
}

func (r *accountDeletionRepository) Schedule(ctx context.Context, userID string) (time.Time, error) {
	raw, err := r.rpc.RPC(ctx, "account_deletion_schedule", map[string]any{"p_actor": userID})
	if err != nil {
		return time.Time{}, err
	}
	var result struct {
		DeleteAfter time.Time `json:"delete_after"`
	}
	if json.Unmarshal(raw, &result) != nil || result.DeleteAfter.IsZero() {
		return time.Time{}, errors.New("invalid account deletion schedule")
	}
	return result.DeleteAfter, nil
}

func (r *accountDeletionRepository) Restore(ctx context.Context, userID, sessionID string) error {
	_, err := r.rpc.RPC(ctx, "account_deletion_restore", map[string]any{"p_actor": userID, "p_session": sessionID})
	return err
}

func (r *accountDeletionRepository) ClaimDue(ctx context.Context, limit int) ([]domain.AccountDeletionJob, error) {
	raw, err := r.rpc.RPC(ctx, "account_deletion_claim", map[string]any{"p_limit": limit})
	if err != nil {
		return nil, err
	}
	var jobs []domain.AccountDeletionJob
	if err := json.Unmarshal(raw, &jobs); err != nil {
		return nil, err
	}
	return jobs, nil
}

func (r *accountDeletionRepository) RemoveFiles(ctx context.Context, files []domain.AccountDeletionFile) error {
	byBucket := make(map[string][]string)
	for _, file := range files {
		if file.Bucket == "" || file.Path == "" {
			return errors.New("invalid account deletion file")
		}
		byBucket[file.Bucket] = append(byBucket[file.Bucket], file.Path)
	}
	for bucket, paths := range byBucket {
		for start := 0; start < len(paths); start += 100 {
			if err := r.storage.remove(ctx, bucket, paths[start:min(start+100, len(paths))]); err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *accountDeletionRepository) Complete(ctx context.Context, userID, leaseToken string) error {
	_, err := r.rpc.RPC(ctx, "account_deletion_complete", map[string]any{"p_actor": userID, "p_lease": leaseToken})
	return err
}
