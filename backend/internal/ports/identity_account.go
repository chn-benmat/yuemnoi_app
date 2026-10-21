package ports

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type identityAccount struct {
	Raw            string          `json:"raw_encrypted"`
	LockedHMAC     string          `json:"locked_hmac"`
	MaskedID       string          `json:"masked_id"`
	HasIdentity    bool            `json:"has_identity"`
	SelfieWithCard bool            `json:"selfie_with_card"`
	Status         json.RawMessage `json:"status"`
	Evidence       []struct {
		ID   string `json:"id"`
		Kind string `json:"kind"`
	} `json:"evidence"`
}

func (h *OperationsHandler) account(c fiber.Ctx, user string) (*identityAccount, error) {
	raw, err := h.options.Store.RPC(c.Context(), "identity_account_details", map[string]any{"p_actor": user})
	if err != nil {
		return nil, err
	}
	var account identityAccount
	if err = json.Unmarshal(raw, &account); err != nil {
		return nil, err
	}
	return &account, nil
}

func (h *OperationsHandler) AccountDetails(c fiber.Ctx) error {
	user, ok := h.actor(c)
	if !ok {
		return nil
	}
	account, err := h.account(c, user)
	if err != nil {
		return operationError(c, err)
	}
	fields := map[string]any{}
	if account.Raw != "" {
		plain, err := domain.DecryptIdentity(account.Raw, h.options.EncryptionKey)
		if err != nil {
			return operationError(c, err)
		}
		if err = json.Unmarshal(plain, &fields); err != nil {
			return operationError(c, err)
		}
	}
	if fields["citizen_id"] == nil || fields["citizen_id"] == "" {
		fields["citizen_id"] = account.MaskedID
	}
	return c.JSON(fiber.Map{"fields": fields, "status": account.Status, "has_identity": account.HasIdentity, "selfie_with_card": account.SelfieWithCard, "evidence": account.Evidence})
}

type identityOwnerEvidence struct {
	Path           string `json:"object_path"`
	Kind           string `json:"kind"`
	SelfieWithCard bool   `json:"selfie_with_card"`
}

func (h *OperationsHandler) ownerEvidenceInfo(c fiber.Ctx, user, id, kind string) (*identityOwnerEvidence, error) {
	if !validUUID(id) {
		return nil, errors.New("evidence_unavailable")
	}
	raw, err := h.options.Store.RPC(c.Context(), "identity_owner_evidence", map[string]any{"p_actor": user, "p_id": id})
	if err != nil {
		return nil, err
	}
	var evidence identityOwnerEvidence
	if json.Unmarshal(raw, &evidence) != nil || evidence.Path == "" {
		return nil, errors.New("evidence_unavailable")
	}
	// รูปเดิมอาจไม่มีธงรุ่นใหม่ แต่ยังต้องเป็นของเจ้าของคำขอและชนิดตรงกัน
	if kind != "" && evidence.Kind != kind {
		return nil, errors.New("evidence_unavailable")
	}
	return &evidence, nil
}

func (h *OperationsHandler) ownerEvidence(c fiber.Ctx, user, id, kind string) ([]byte, string, error) {
	evidence, err := h.ownerEvidenceInfo(c, user, id, kind)
	if err != nil {
		return nil, "", err
	}
	return h.options.Store.ReadEvidence(c.Context(), evidence.Path)
}

func (h *OperationsHandler) AccountEvidence(c fiber.Ctx) error {
	user, ok := h.actor(c)
	if !ok {
		return nil
	}
	data, content, err := h.ownerEvidence(c, user, c.Params("id"), "")
	if err != nil {
		return operationError(c, err)
	}
	if content != "image/jpeg" && content != "image/png" {
		return c.SendStatus(415)
	}
	return c.JSON(fiber.Map{"data": base64.StdEncoding.EncodeToString(data)})
}
