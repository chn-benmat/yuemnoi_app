package supabase_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestCreateItemStoresImagesUnderOwnerAndCreatedItem(t *testing.T) {
	var paths, savedURLs []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/rest/v1/item_tb" && r.Method == http.MethodPost:
			_, _ = w.Write([]byte(`[{"id":73,"user_id":"owner-user"}]`))
		case strings.HasPrefix(r.URL.Path, "/storage/v1/object/item_bk/"):
			paths = append(paths, r.URL.Path)
			if r.Header.Get("Content-Type") != "image/jpeg" {
				t.Error("image content type changed")
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"Key": r.URL.Path})
		case r.URL.Path == "/rest/v1/item_tb" && r.Method == http.MethodPatch:
			var payload struct {
				URLs []string `json:"item_image_url"`
			}
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Error(err)
			}
			savedURLs = payload.URLs
			_ = json.NewEncoder(w).Encode([]map[string]any{{"id": 73, "user_id": "owner-user", "item_image_url": savedURLs}})
		default:
			t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repository := supabase.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	image := domain.ItemImage{Data: []byte("image"), ContentType: "image/jpeg", Extension: ".jpg"}
	item, err := repository.Insert(context.Background(), &domain.Item{UserID: "owner-user"}, []domain.ItemImage{image, image})
	if err != nil {
		t.Fatal(err)
	}
	if len(paths) != 2 || len(savedURLs) != 2 || len(item.ItemImageURL) != 2 {
		t.Fatalf("uploads=%v saved=%v item=%+v", paths, savedURLs, item)
	}
	for i, path := range paths {
		if !strings.HasPrefix(path, "/storage/v1/object/item_bk/owner-user/73/") {
			t.Errorf("upload path = %q", path)
		}
		if want := server.URL + strings.Replace(path, "/object/", "/object/public/", 1); savedURLs[i] != want {
			t.Errorf("saved URL = %q, want %q", savedURLs[i], want)
		}
	}
	if paths[0] == paths[1] {
		t.Error("multiple images overwrite the same object")
	}
}

func TestProfileImageStorageUsesOwnerFolder(t *testing.T) {
	for _, operation := range []string{"registration", "update"} {
		t.Run(operation, func(t *testing.T) {
			var uploadPath, savedURL, returnedURL string
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if strings.HasPrefix(r.URL.Path, "/rest/v1/") {
					wantSchema := "public"
					if r.URL.Path == "/rest/v1/profile_tb" {
						wantSchema = "profiles"
					}
					for _, header := range []string{"Accept-Profile", "Content-Profile"} {
						if got := r.Header.Get(header); got != wantSchema {
							t.Errorf("%s %s %s = %q, want %q", r.Method, r.URL.Path, header, got, wantSchema)
						}
					}
				}
				switch {
				case r.URL.Path == "/rest/v1/rpc/check_email_exists":
					_, _ = w.Write([]byte(`false`))
				case r.URL.Path == "/auth/v1/admin/users":
					_, _ = w.Write([]byte(`{"id":"profile-owner"}`))
				case strings.HasPrefix(r.URL.Path, "/storage/v1/object/profile_bk/"):
					uploadPath = r.URL.Path
					_ = json.NewEncoder(w).Encode(map[string]string{"Key": uploadPath})
				case r.URL.Path == "/rest/v1/profile_tb" && r.Method == http.MethodPatch:
					var payload struct {
						URL string `json:"user_image_url"`
					}
					if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
						t.Error(err)
					}
					savedURL = payload.URL
					_, _ = w.Write([]byte(`[{"user_id":"profile-owner"}]`))
				case r.URL.Path == "/rest/v1/profile_tb" && r.Method == http.MethodGet:
					_ = json.NewEncoder(w).Encode([]map[string]string{{"user_id": "profile-owner", "user_image_url": savedURL}})
				case r.URL.Path == "/auth/v1/admin/users/profile-owner":
					_, _ = w.Write([]byte(`{"id":"profile-owner"}`))
				default:
					t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			defer server.Close()
			client := supabaseclient.CreateClient(server.URL, "test-key")
			repository := supabase.NewSupabaseUserRepository(client, "test-key")
			image := &domain.ProfileImage{Data: []byte("image"), ContentType: "image/png", Extension: ".png"}
			if operation == "registration" {
				result, err := repository.Register(context.Background(), domain.RegisterUser{Email: "owner@example.com", ProfileImage: image})
				if err != nil {
					t.Fatal(err)
				}
				returnedURL = result.UserImageURL
			} else {
				result, err := repository.UpdateProfile(context.Background(), "profile-owner", domain.UpdateProfileRequest{}, image)
				if err != nil {
					t.Fatal(err)
				}
				returnedURL = result.UserImageURL
			}
			if !strings.HasPrefix(uploadPath, "/storage/v1/object/profile_bk/profile-owner/") || !strings.HasSuffix(uploadPath, ".png") {
				t.Errorf("upload path = %q", uploadPath)
			}
			wantURL := server.URL + strings.Replace(uploadPath, "/object/", "/object/public/", 1)
			if savedURL != wantURL || returnedURL != wantURL {
				t.Errorf("saved=%q returned=%q want=%q", savedURL, returnedURL, wantURL)
			}
		})
	}
}
