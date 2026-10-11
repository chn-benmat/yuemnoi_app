package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// จำลองเฉพาะตารางที่เกี่ยวข้อง เพื่อทดสอบ Storage ผ่าน repository จริงทั้งสองตัว
func storageRepositoryResponse(t *testing.T, w http.ResponseWriter, r *http.Request) {
	t.Helper()
	w.Header().Set("Content-Type", "application/json")
	switch r.URL.Path {
	case "/rest/v1/item_tb":
		if r.Method == http.MethodDelete {
			w.WriteHeader(204)
			return
		}
		_, _ = io.WriteString(w, `[{"id":7,"user_id":"fixture-user","item_image_url":[]}]`)
	case "/rest/v1/profile_tb":
		if r.URL.Query().Get("user_image_url") != "" {
			_, _ = io.WriteString(w, `[]`)
			return
		}
		_, _ = io.WriteString(w, `[{"user_id":"fixture-user","user_image_url":"https://example.test/image.png"}]`)
	case "/auth/v1/admin/users/fixture-user":
		_, _ = io.WriteString(w, `{"id":"fixture-user","email":"fixture@example.test"}`)
	default:
		t.Errorf("unexpected repository request: %s %s", r.Method, r.URL.Path)
		http.NotFound(w, r)
	}
}

func uploadViaRepository(client *supabaseclient.Client, target string, ctx context.Context) error {
	if target == "profile" {
		repo := supabaseadapter.NewSupabaseUserRepository(client, "fixture-key")
		_, err := repo.UpdateProfile(ctx, "fixture-user", domain.UpdateProfileRequest{}, &domain.ProfileImage{
			Data: []byte("fixture-image"), ContentType: "image/png", Extension: ".png",
		})
		return err
	}
	repo := supabaseadapter.NewSupabaseItemRepository(client, "fixture-key")
	_, err := repo.Insert(ctx, &domain.Item{UserID: "fixture-user", ItemName: "camera"}, []domain.ItemImage{
		{Data: []byte("fixture-image"), ContentType: "image/png", Extension: ".png"},
	})
	return err
}

func TestStorageRejectsHTTPFailuresMalformedJSONAndMissingKeys(t *testing.T) {
	for _, target := range []string{"profile", "item"} {
		for _, tc := range []struct {
			name   string
			status int
			body   string
		}{
			{"unauthorized with misleading key", 401, `{"Key":"must-not-be-accepted"}`},
			{"forbidden", 403, `{"message":"denied"}`},
			{"upstream unavailable", 503, `{"message":"busy"}`},
			{"malformed success body", 200, `not-json`},
			{"missing object key", 200, `{}`},
		} {
			t.Run(target+"/"+tc.name, func(t *testing.T) {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if strings.HasPrefix(r.URL.Path, "/storage/") {
						assert.Equal(t, "POST", r.Method)
						assert.Equal(t, "fixture-key", r.Header.Get("apikey"))
						assert.Equal(t, "Bearer fixture-key", r.Header.Get("Authorization"))
						assert.Equal(t, "3600", r.Header.Get("Cache-Control"))
						assert.Equal(t, "false", r.Header.Get("x-upsert"))
						data, err := io.ReadAll(r.Body)
						assert.NoError(t, err)
						assert.Equal(t, "fixture-image", string(data))
						w.WriteHeader(tc.status)
						_, _ = io.WriteString(w, tc.body)
						return
					}
					storageRepositoryResponse(t, w, r)
				}))
				defer server.Close()
				client := supabaseclient.CreateClient(server.URL, "fixture-key")
				require.Error(t, uploadViaRepository(client, target, context.Background()))
			})
		}
	}
}

func TestStorageHonorsHTTPTimeoutWhileWaitingForHeadersAndBody(t *testing.T) {
	for _, target := range []string{"profile", "item"} {
		for _, stage := range []string{"headers", "body"} {
			t.Run(target+"/"+stage, func(t *testing.T) {
				release := make(chan struct{})
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if strings.HasPrefix(r.URL.Path, "/storage/") {
						_, _ = io.Copy(io.Discard, r.Body)
						if stage == "body" {
							_, _ = io.WriteString(w, `{"Key":"`)
							w.(http.Flusher).Flush()
						}
						select {
						case <-r.Context().Done():
						case <-release:
						}
						return
					}
					storageRepositoryResponse(t, w, r)
				}))
				defer server.Close()
				defer close(release)
				client := supabaseclient.CreateClient(server.URL, "fixture-key")
				client.HTTPClient.Timeout = 40 * time.Millisecond
				started := time.Now()
				err := uploadViaRepository(client, target, context.Background())
				require.ErrorIs(t, err, context.DeadlineExceeded)
				require.Less(t, time.Since(started), time.Second)
			})
		}
	}
}

func TestStorageHonorsCallerCancellation(t *testing.T) {
	for _, target := range []string{"profile", "item"} {
		t.Run(target, func(t *testing.T) {
			started, release := make(chan struct{}), make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if strings.HasPrefix(r.URL.Path, "/storage/") {
					_, _ = io.Copy(io.Discard, r.Body)
					close(started)
					select {
					case <-r.Context().Done():
					case <-release:
					}
					return
				}
				storageRepositoryResponse(t, w, r)
			}))
			defer server.Close()
			defer close(release)
			client := supabaseclient.CreateClient(server.URL, "fixture-key")
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan error, 1)
			go func() { done <- uploadViaRepository(client, target, ctx) }()
			select {
			case <-started:
			case <-time.After(time.Second):
				t.Fatal("upload did not reach upstream")
			}
			cancel()
			select {
			case err := <-done:
				require.ErrorIs(t, err, context.Canceled)
			case <-time.After(time.Second):
				t.Fatal("upload ignored cancellation")
			}
		})
	}
}

func TestStorageCleansUploadedFilesWhenDatabaseSaveFails(t *testing.T) {
	for _, target := range []string{"profile", "item"} {
		for _, cause := range []string{"http error", "cancelled caller", "missing row"} {
			t.Run(target+"/"+cause, func(t *testing.T) {
				ctx, cancel := context.WithCancel(context.Background())
				defer cancel()
				uploaded := make(chan string, 1)
				removed := make(chan []string, 1)
				var deletedRows atomic.Int32
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if strings.HasPrefix(r.URL.Path, "/storage/") {
						w.Header().Set("Content-Type", "application/json")
						if r.Method == "POST" {
							_, _ = io.Copy(io.Discard, r.Body)
							path := strings.TrimPrefix(r.URL.Path, "/storage/v1/object/"+map[string]string{"profile": "profile_bk/", "item": "item_bk/"}[target])
							uploaded <- path
							_ = json.NewEncoder(w).Encode(map[string]string{"Key": path})
						} else {
							var body struct {
								Prefixes []string `json:"prefixes"`
							}
							assert.NoError(t, json.NewDecoder(r.Body).Decode(&body))
							removed <- body.Prefixes
							_, _ = io.WriteString(w, `[]`)
						}
						return
					}
					if r.Method == "PATCH" {
						_, _ = io.Copy(io.Discard, r.Body)
						if cause == "cancelled caller" {
							cancel()
						}
						if cause == "missing row" {
							_, _ = io.WriteString(w, `[]`)
							return
						}
						w.WriteHeader(500)
						_, _ = io.WriteString(w, `{"message":"save failed"}`)
						return
					}
					if r.Method == "DELETE" {
						deletedRows.Add(1)
					}
					storageRepositoryResponse(t, w, r)
				}))
				defer server.Close()
				client := supabaseclient.CreateClient(server.URL, "fixture-key")
				require.Error(t, uploadViaRepository(client, target, ctx))
				require.Equal(t, []string{<-uploaded}, <-removed)
				if target == "item" {
					require.EqualValues(t, 1, deletedRows.Load())
				}
			})
		}
	}
}

func TestSupabaseAuthAndDatabasePreserveContextCancellation(t *testing.T) {
	for _, target := range []string{"auth", "database headers", "database body"} {
		t.Run(target, func(t *testing.T) {
			release := make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = io.Copy(io.Discard, r.Body)
				if target == "database body" {
					_, _ = io.WriteString(w, `[{`)
					w.(http.Flusher).Flush()
				}
				select {
				case <-r.Context().Done():
				case <-release:
				}
			}))
			defer server.Close()
			defer close(release)
			client := supabaseadapter.InitSupabaseClient(server.URL, "fixture-key")
			require.Equal(t, time.Minute, client.HTTPClient.Timeout)
			ctx, cancel := context.WithTimeout(context.Background(), 40*time.Millisecond)
			defer cancel()
			var err error
			if target == "auth" {
				_, err = supabaseadapter.NewSupabaseUserRepository(client, "fixture-key").UserIDFromToken(ctx, "fixture-token")
			} else {
				_, err = supabaseadapter.NewSupabaseItemRepository(client, "fixture-key").FindByID(ctx, 7)
			}
			require.ErrorIs(t, err, context.DeadlineExceeded)
		})
	}
}

func TestStorageKeepsProfileImageIfSaveOutcomeIsUncertain(t *testing.T) {
	for _, state := range []string{"already referenced", "cannot verify references"} {
		t.Run(state, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			var removals atomic.Int32
			var checks atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if strings.HasPrefix(r.URL.Path, "/storage/") {
					if r.Method == "DELETE" {
						removals.Add(1)
					}
					_, _ = io.Copy(io.Discard, r.Body)
					_, _ = io.WriteString(w, `{"Key":"uploaded-image"}`)
					return
				}
				if r.Method == "PATCH" {
					_, _ = io.Copy(io.Discard, r.Body)
					cancel()
					return
				}
				checks.Add(1)
				assert.NotEmpty(t, r.URL.Query().Get("user_image_url"))
				if state == "cannot verify references" {
					w.WriteHeader(500)
					_, _ = io.WriteString(w, `{"message":"database unavailable"}`)
				} else {
					_, _ = io.WriteString(w, `[{"user_id":"fixture-user"}]`)
				}
			}))
			defer server.Close()
			client := supabaseclient.CreateClient(server.URL, "fixture-key")
			require.ErrorIs(t, uploadViaRepository(client, "profile", ctx), context.Canceled)
			require.EqualValues(t, 1, checks.Load())
			require.Zero(t, removals.Load())
		})
	}
}

func TestStorageKeepsItemImagesIfRollbackRowDeletionFails(t *testing.T) {
	var removals atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if strings.HasPrefix(r.URL.Path, "/storage/") {
			if r.Method == "DELETE" {
				removals.Add(1)
			}
			_, _ = io.Copy(io.Discard, r.Body)
			_, _ = io.WriteString(w, `{"Key":"uploaded-image"}`)
			return
		}
		if r.Method == "PATCH" || r.Method == "DELETE" {
			w.WriteHeader(409)
			_, _ = io.WriteString(w, `{"code":"23503","message":"referenced item"}`)
			return
		}
		storageRepositoryResponse(t, w, r)
	}))
	defer server.Close()
	client := supabaseclient.CreateClient(server.URL, "fixture-key")
	require.Error(t, uploadViaRepository(client, "item", context.Background()))
	require.Zero(t, removals.Load())
}
