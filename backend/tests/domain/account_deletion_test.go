package domain_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type deletionWorkerStore struct {
	domain.AccountDeletionRepository
	err       error
	completed []string
}

func (s *deletionWorkerStore) ClaimDue(context.Context, int) ([]domain.AccountDeletionJob, error) {
	return []domain.AccountDeletionJob{
		{UserID: "retry", LeaseToken: "lease-1", Files: []domain.AccountDeletionFile{{Bucket: "identity-private", Path: "retry"}}},
		{UserID: "ready", LeaseToken: "lease-2", Files: []domain.AccountDeletionFile{{Bucket: "item_bk", Path: "ready"}}},
	}, nil
}

func (s *deletionWorkerStore) RemoveFiles(_ context.Context, files []domain.AccountDeletionFile) error {
	if files[0].Path == "retry" {
		return s.err
	}
	return nil
}

func (s *deletionWorkerStore) Complete(_ context.Context, userID, token string) error {
	s.completed = append(s.completed, userID+"/"+token)
	return nil
}

func TestAccountDeletionWorkerCompletesOnlyWhenStorageSucceeds(t *testing.T) {
	outage := errors.New("storage unavailable")
	store := &deletionWorkerStore{err: outage}
	if err := domain.ProcessAccountDeletions(context.Background(), store); !errors.Is(err, outage) {
		t.Fatalf("expected retry error, got %v", err)
	}
	if !reflect.DeepEqual(store.completed, []string{"ready/lease-2"}) {
		t.Fatalf("completed = %v", store.completed)
	}
}
