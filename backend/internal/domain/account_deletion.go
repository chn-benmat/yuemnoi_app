package domain

import (
	"context"
	"errors"
	"time"
)

type PendingAccountDeletion struct {
	UserID      string
	DeleteAfter time.Time
}

func (e *PendingAccountDeletion) Error() string { return "account_deletion_pending" }

type AccountDeletionFile struct {
	Bucket string `json:"bucket"`
	Path   string `json:"path"`
}

type AccountDeletionJob struct {
	UserID     string                `json:"user_id"`
	LeaseToken string                `json:"lease_token"`
	Files      []AccountDeletionFile `json:"files"`
}

type AccountDeletionRepository interface {
	Schedule(context.Context, string) (time.Time, error)
	Restore(context.Context, string, string) error
	ClaimDue(context.Context, int) ([]AccountDeletionJob, error)
	RemoveFiles(context.Context, []AccountDeletionFile) error
	Complete(context.Context, string, string) error
}

func ProcessAccountDeletions(ctx context.Context, repository AccountDeletionRepository) error {
	jobs, err := repository.ClaimDue(ctx, 5)
	if err != nil {
		return err
	}
	var failures error
	for _, job := range jobs {
		// ยืนยันการลบบัญชีหลัง Storage ลบไฟล์ครบ แล้วปล่อยให้ lease หมดอายุเพื่อทำซ้ำเมื่อขัดข้อง
		if err := repository.RemoveFiles(ctx, job.Files); err != nil {
			failures = errors.Join(failures, err)
			continue
		}
		failures = errors.Join(failures, repository.Complete(ctx, job.UserID, job.LeaseToken))
	}
	return failures
}
