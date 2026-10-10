package aiservice

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

type identityClient struct {
	base, key string
	client    *http.Client
}

func NewIdentityClient(base, key string, timeout time.Duration) domain.IdentityAnalyzer {
	return &identityClient{strings.TrimRight(base, "/"), key, &http.Client{Timeout: timeout}}
}
func (c *identityClient) AnalyzeIdentity(ctx context.Context, card, selfie []byte) (*domain.IdentityAnalysis, error) {
	var result domain.IdentityAnalysis
	err := c.identityRequest(ctx, "/api/identity/analyze", map[string][]byte{"card": card, "selfie": selfie}, &result)
	return &result, err
}
func (c *identityClient) ReadIdentityCard(ctx context.Context, card []byte) (*domain.IdentityOCR, error) {
	var result domain.IdentityOCR
	err := c.identityRequest(ctx, "/api/identity/read-card", map[string][]byte{"card": card}, &result)
	return &result, err
}
func (c *identityClient) identityRequest(ctx context.Context, path string, files map[string][]byte, result any) error {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for name, data := range files {
		part, err := writer.CreateFormFile(name, name+".jpg")
		if err != nil {
			return err
		}
		if _, err = part.Write(data); err != nil {
			return err
		}
	}
	if err := writer.Close(); err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", c.base+path, &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("X-Internal-Service-Key", c.key)
	res, err := c.client.Do(req)
	if err != nil {
		return errors.New("identity_analysis_unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return errors.New("identity_analysis_unavailable")
	}
	if err = json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(result); err != nil {
		return errors.New("identity_analysis_unavailable")
	}
	return nil
}
func (c *identityClient) IdentityReady(ctx context.Context) bool {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", c.base+"/api/identity/health", nil)
	if err != nil {
		return false
	}
	req.Header.Set("X-Internal-Service-Key", c.key)
	res, err := c.client.Do(req)
	if err != nil {
		return false
	}
	defer res.Body.Close()
	return res.StatusCode == 200
}
