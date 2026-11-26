package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/nedpals/supabase-go"
)

const (
	supabaseRequestTimeout = time.Minute
	storageCleanupTimeout  = 5 * time.Second
)

// storageClient ใช้ HTTP client ร่วมกับ Auth โดยส่ง context และคืน error แทน panic
type storageClient struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

func newStorageClient(client *supabase.Client, apiKey string) *storageClient {
	httpClient := http.Client{Timeout: supabaseRequestTimeout}
	if client.HTTPClient != nil {
		httpClient = *client.HTTPClient
		if httpClient.Timeout <= 0 {
			httpClient.Timeout = supabaseRequestTimeout
		}
	}
	return &storageClient{strings.TrimRight(client.BaseURL, "/"), apiKey, &httpClient}
}

func escapedStoragePath(bucket, path string) string {
	parts := strings.Split(path, "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return url.PathEscape(bucket) + "/" + strings.Join(parts, "/")
}

func (s *storageClient) publicURL(bucket, path string) string {
	return s.baseURL + "/storage/v1/object/public/" + escapedStoragePath(bucket, path)
}

func (s *storageClient) upload(ctx context.Context, bucket, path string, data []byte, contentType string) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost,
		s.baseURL+"/storage/v1/object/"+escapedStoragePath(bucket, path), bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("create storage upload request: %w", err)
	}
	request.Header.Set("Content-Type", contentType)
	request.Header.Set("Cache-Control", "3600")
	request.Header.Set("x-upsert", "false")
	response, err := s.do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	var result struct {
		Key string `json:"Key"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&result); err != nil {
		return fmt.Errorf("decode storage upload response: %w", err)
	}
	if result.Key == "" {
		return fmt.Errorf("storage upload response did not contain an object key")
	}
	return nil
}

func (s *storageClient) remove(ctx context.Context, bucket string, paths []string) error {
	if len(paths) == 0 {
		return nil
	}
	data, err := json.Marshal(map[string]any{"prefixes": paths})
	if err != nil {
		return fmt.Errorf("encode storage removal request: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodDelete,
		s.baseURL+"/storage/v1/object/"+url.PathEscape(bucket), bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("create storage removal request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := s.do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, err = io.Copy(io.Discard, io.LimitReader(response.Body, 1<<20))
	return err
}

func (s *storageClient) do(request *http.Request) (*http.Response, error) {
	request.Header.Set("apikey", s.apiKey)
	request.Header.Set("Authorization", "Bearer "+s.apiKey)
	response, err := s.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("Supabase Storage request failed: %w", err)
	}
	if request.Method == http.MethodDelete && response.StatusCode == http.StatusNotFound {
		return response, nil
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		defer response.Body.Close()
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 1<<20))
		return nil, fmt.Errorf("Supabase Storage returned HTTP %d", response.StatusCode)
	}
	return response, nil
}
