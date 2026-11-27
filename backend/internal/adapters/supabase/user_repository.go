package supabase

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

const profileBucket = "profile_bk"
const signupRedirect = "yuemnoi://login-callback/"

type supabaseUserRepository struct {
	client     *supabase.Client
	authAPIKey string
	storage    *storageClient
}

func NewSupabaseUserRepository(sbClient *supabase.Client, authAPIKey string) domain.AuthGateway {
	return &supabaseUserRepository{
		client:     sbClient,
		authAPIKey: authAPIKey,
		storage:    newStorageClient(sbClient, authAPIKey),
	}
}

func (r *supabaseUserRepository) UserIDFromToken(ctx context.Context, userToken string) (string, error) {
	user, err := r.authIdentity(ctx, userToken)
	if err != nil {
		return "", err
	}
	return user.accountAccess()
}

// อ่าน app_metadata ล่าสุดจาก Auth เพื่อให้ session เดิมถูกจำกัดได้ทันที
func (r *supabaseUserRepository) AppUserIDFromToken(ctx context.Context, userToken string) (string, error) {
	user, err := r.authIdentity(ctx, userToken)
	if err != nil {
		return "", err
	}
	if user.AppMetadata.DashboardOnly {
		return "", domain.ErrDashboardOnly
	}
	return user.accountAccess()
}

type authIdentity struct {
	ID          string `json:"id"`
	AppMetadata struct {
		DashboardOnly      bool       `json:"dashboard_only"`
		AccountDeleteAfter *time.Time `json:"account_delete_after"`
	} `json:"app_metadata"`
}

func (u authIdentity) accountAccess() (string, error) {
	if u.AppMetadata.AccountDeleteAfter != nil {
		return "", &domain.PendingAccountDeletion{UserID: u.ID, DeleteAfter: *u.AppMetadata.AccountDeleteAfter}
	}
	return u.ID, nil
}

func (r *supabaseUserRepository) authIdentity(ctx context.Context, token string) (*authIdentity, error) {
	endpoint := strings.TrimRight(r.client.BaseURL, "/") + "/auth/v1/user"
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("create Auth identity request: %w", err)
	}
	request.Header.Set("apikey", r.authAPIKey)
	request.Header.Set("Authorization", "Bearer "+token)
	response, err := r.client.HTTPClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("verify Auth identity: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, domain.ErrInvalidAccessToken
	}
	var user authIdentity
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&user); err != nil {
		return nil, fmt.Errorf("decode Auth identity: %w", err)
	}
	if user.ID == "" {
		return nil, domain.ErrInvalidAccessToken
	}
	return &user, nil
}

// SyncGoogleProfileImage copies the Google avatar URL from Supabase Auth
// metadata into the application's profile row.
func (r *supabaseUserRepository) SyncGoogleProfileImage(ctx context.Context, userToken string) (string, error) {
	user, err := r.client.Auth.User(ctx, userToken)
	if err != nil {
		return "", fmt.Errorf("invalid access token: %w", err)
	}
	if user == nil || user.ID == "" {
		return "", fmt.Errorf("access token does not contain a user")
	}

	imageURL := googleProfileImageURL(user.UserMetadata)
	if imageURL == "" {
		return "", fmt.Errorf("Google profile image URL was not found")
	}

	var updated []map[string]interface{}
	err = schemaDatabase(r.client, profilesSchema).From("profile_tb").
		Update(map[string]interface{}{"user_image_url": imageURL}).
		Eq("user_id", user.ID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return "", fmt.Errorf("failed to save Google profile image URL: %w", err)
	}
	if len(updated) == 0 {
		return "", fmt.Errorf("profile was not found for user %s", user.ID)
	}

	return imageURL, nil
}

func googleProfileImageURL(metadata map[string]interface{}) string {
	for _, key := range []string{"avatar_url", "picture"} {
		if value, ok := metadata[key].(string); ok {
			if imageURL := strings.TrimSpace(value); imageURL != "" {
				return imageURL
			}
		}

	}

	return ""
}

// Login ตรวจสอบสิทธิ์ผ่าน Supabase Auth และส่ง Access Token กลับออกไป
func (r *supabaseUserRepository) Login(ctx context.Context, email, password string) (*domain.AuthTokens, error) {
	// 1. เรียกใช้ client.Auth ให้ถูกจุด และส่ง UserCredentials
	resp, err := r.client.Auth.SignIn(ctx, supabase.UserCredentials{
		Email:    email,
		Password: password,
	})
	if err != nil {
		if strings.HasPrefix(err.Error(), "email_not_confirmed:") {
			return nil, domain.ErrEmailNotConfirmed
		}
		return nil, fmt.Errorf("supabase login failed: %w", err)
	}

	// 2. ตรวจสอบว่าได้ Token กลับมาจริงไหม ป้องกันกรณีเกิดความผิดพลาดภายใน
	if resp.AccessToken == "" {
		return nil, fmt.Errorf("authentication succeeded but no access token returned")
	}
	if resp.RefreshToken == "" {
		return nil, fmt.Errorf("authentication succeeded but no refresh token returned")
	}

	return &domain.AuthTokens{
		AccessToken:  resp.AccessToken,
		RefreshToken: resp.RefreshToken,
	}, nil
}

// Register ส่งคำขอสมัครผ่าน Auth เพื่อให้ Supabase ส่งอีเมลยืนยันเอง
func (r *supabaseUserRepository) Register(ctx context.Context, user domain.RegisterUser) (*domain.RegisterResult, error) {
	authURL := strings.TrimRight(r.client.BaseURL, "/") + "/" + supabase.AuthEndpoint
	if err := r.requireEmailConfirmation(ctx, authURL); err != nil {
		return nil, err
	}

	registrationID := rand.Text()
	payload, err := json.Marshal(map[string]any{
		"email":    user.Email,
		"password": user.Password,
		"data": map[string]string{
			"display_name":    user.DisplayName,
			"phone":           user.Phone,
			"registration_id": registrationID,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("encode Auth signup request: %w", err)
	}

	endpoint := authURL + "/signup?redirect_to=" + url.QueryEscape(signupRedirect)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create Auth signup request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("apikey", r.authAPIKey)
	response, err := r.client.HTTPClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("request Auth signup: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return nil, signupResponseError(response)
	}

	var signup struct {
		ID               string     `json:"id"`
		AccessToken      string     `json:"access_token"`
		EmailConfirmedAt *time.Time `json:"email_confirmed_at"`
		Identities       []struct{} `json:"identities"`
		UserMetadata     struct {
			RegistrationID string `json:"registration_id"`
		} `json:"user_metadata"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&signup); err != nil {
		return nil, fmt.Errorf("decode Auth signup response: %w", err)
	}
	if signup.AccessToken != "" || signup.EmailConfirmedAt != nil {
		return nil, domain.ErrRegistrationConfirmationUnavailable
	}
	if signup.ID == "" {
		return nil, fmt.Errorf("Auth signup response is missing a user ID")
	}
	// Supabase คืนบัญชีเดิมเมื่อส่งลิงก์ซ้ำ และคืนข้อมูลจำลองสำหรับบัญชีที่ยืนยันแล้ว
	if len(signup.Identities) == 0 || signup.UserMetadata.RegistrationID != registrationID {
		return &domain.RegisterResult{}, nil
	}

	result, err := r.completeRegistration(ctx, user, signup.ID)
	if err != nil {
		// ส่งลิงก์ยืนยันแล้ว ผู้ใช้ยังเข้าสู่ระบบและเพิ่มรูปภายหลังได้
		slog.Warn("บันทึกรูปโปรไฟล์ขณะสมัครไม่สำเร็จ")
		return &domain.RegisterResult{UserID: signup.ID}, nil
	}
	return result, nil
}

func (r *supabaseUserRepository) requireEmailConfirmation(ctx context.Context, authURL string) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, authURL+"/settings", nil)
	if err != nil {
		return fmt.Errorf("create Auth settings request: %w", err)
	}
	request.Header.Set("apikey", r.authAPIKey)
	response, err := r.client.HTTPClient.Do(request)
	if err != nil {
		return fmt.Errorf("load Auth settings: %w", err)
	}
	defer response.Body.Close()

	var settings struct {
		MailerAutoconfirm *bool `json:"mailer_autoconfirm"`
	}
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("load Auth settings: HTTP %d", response.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&settings); err != nil {
		return fmt.Errorf("decode Auth settings: %w", err)
	}
	if settings.MailerAutoconfirm == nil || *settings.MailerAutoconfirm {
		return domain.ErrRegistrationConfirmationUnavailable
	}
	return nil
}

func signupResponseError(response *http.Response) error {
	var authError struct {
		Code string `json:"error_code"`
	}
	_ = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&authError)
	switch {
	case authError.Code == "user_already_exists" || authError.Code == "email_exists":
		return domain.ErrRegistrationEmailTaken
	case authError.Code == "email_address_invalid" || authError.Code == "validation_failed":
		return domain.ErrRegistrationInputInvalid
	case authError.Code == "weak_password":
		return domain.ErrRegistrationPasswordWeak
	case authError.Code == "email_address_not_authorized",
		authError.Code == "signup_disabled",
		authError.Code == "email_provider_disabled":
		return domain.ErrRegistrationConfirmationUnavailable
	case response.StatusCode == http.StatusTooManyRequests:
		return domain.ErrRegistrationRateLimited
	default:
		return fmt.Errorf("Auth signup failed: HTTP %d (%s)", response.StatusCode, authError.Code)
	}
}

func (r *supabaseUserRepository) completeRegistration(ctx context.Context, user domain.RegisterUser, userID string) (*domain.RegisterResult, error) {
	result := &domain.RegisterResult{UserID: userID}
	if user.ProfileImage == nil {
		return result, nil
	}

	objectPath := fmt.Sprintf("%s/profile-%d%s", userID, time.Now().UTC().UnixNano(), user.ProfileImage.Extension)
	err := r.uploadProfileImage(ctx, objectPath, user.ProfileImage)
	if err != nil {
		return nil, err
	}

	publicURL := r.storage.publicURL(profileBucket, objectPath)

	var updated []map[string]interface{}
	err = schemaDatabase(r.client, profilesSchema).From("profile_tb").
		Update(map[string]interface{}{"user_image_url": publicURL}).
		Eq("user_id", userID).
		Is("user_image_url", "null").
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		r.removeProfileImage(ctx, objectPath)
		return nil, fmt.Errorf("failed to save profile image URL: %w", err)
	}
	if len(updated) == 0 {
		r.removeProfileImage(ctx, objectPath)
		return nil, fmt.Errorf("registered profile has no available image field")
	}

	result.UserImageURL = publicURL
	return result, nil
}

func (r *supabaseUserRepository) uploadProfileImage(ctx context.Context, path string, image *domain.ProfileImage) error {
	if err := r.storage.upload(ctx, profileBucket, path, image.Data, image.ContentType); err != nil {
		return fmt.Errorf("profile image upload failed: %w", err)
	}
	return nil
}

func (r *supabaseUserRepository) removeProfileImage(ctx context.Context, path string) {
	// ชดเชยไฟล์ที่อัปโหลดแล้วได้แม้คำขอหลักถูกยกเลิก โดยจำกัดเวลาแยกไว้
	cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), storageCleanupTimeout)
	defer cancel()
	// การตัดการเชื่อมต่ออาจเกิดหลัง DB บันทึกสำเร็จ จึงตรวจการอ้างอิงก่อนลบไฟล์
	var references []map[string]interface{}
	err := schemaDatabase(r.client, profilesSchema).From("profile_tb").Select("user_id").
		Eq("user_image_url", r.storage.publicURL(profileBucket, path)).
		ExecuteWithContext(cleanupCtx, &references)
	if err != nil {
		slog.Warn("ยังลบรูปโปรไฟล์ไม่ได้ เพราะตรวจการอ้างอิงในฐานข้อมูลไม่สำเร็จ")
		return
	}
	if len(references) > 0 {
		return
	}
	if err := r.storage.remove(cleanupCtx, profileBucket, []string{path}); err != nil {
		slog.Warn("ลบรูปโปรไฟล์หลังบันทึกไม่สำเร็จไม่ได้")
	}
}

// ChangePassword เปลี่ยนรหัสผ่านของผู้ใช้ผ่าน Supabase Auth
func (r *supabaseUserRepository) ChangePassword(ctx context.Context, userToken, newPassword string) error {
	payload, err := json.Marshal(map[string]string{
		"password": newPassword,
	})
	if err != nil {
		return fmt.Errorf("failed to encode password update request: %w", err)
	}

	requestURL := strings.TrimRight(r.client.BaseURL, "/") + "/" + supabase.AuthEndpoint + "/user"
	request, err := http.NewRequestWithContext(ctx, http.MethodPut, requestURL, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("failed to create password update request: %w", err)
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("apikey", r.authAPIKey)
	request.Header.Set("Authorization", "Bearer "+userToken)

	response, err := r.client.HTTPClient.Do(request)
	if err != nil {
		return fmt.Errorf("supabase update password failed: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		authErr := decodeAuthAPIError(response)
		if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
			return fmt.Errorf("%w: %v", domain.ErrInvalidAccessToken, authErr)
		}
		return authErr
	}

	return nil
}

// decodeAuthAPIError supports both the current GoTrue error shape
// (error_code/msg) and older shapes used by Supabase Auth clients. The
// supabase-go v0.5.0 UpdateUser implementation only decodes "message", which
// turns valid error responses such as bad_jwt into an empty error string.
func decodeAuthAPIError(response *http.Response) error {
	var body struct {
		Code             json.RawMessage `json:"code"`
		ErrorCode        string          `json:"error_code"`
		Message          string          `json:"message"`
		Msg              string          `json:"msg"`
		ErrorDescription string          `json:"error_description"`
		Error            string          `json:"error"`
	}

	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		return fmt.Errorf("supabase update password failed: HTTP %d", response.StatusCode)
	}

	message := firstNonEmpty(
		body.Msg,
		body.Message,
		body.ErrorDescription,
		body.Error,
		body.ErrorCode,
		string(body.Code),
	)
	if message == "" {
		message = http.StatusText(response.StatusCode)
	}

	code := firstNonEmpty(body.ErrorCode, normalizedJSONValue(body.Code))
	if code != "" && !strings.Contains(strings.ToLower(message), strings.ToLower(code)) {
		message = code + ": " + message
	}

	return fmt.Errorf("supabase update password failed: %s", message)
}

func normalizedJSONValue(value json.RawMessage) string {
	if len(value) == 0 {
		return ""
	}

	var text string
	if err := json.Unmarshal(value, &text); err == nil {
		return strings.TrimSpace(text)
	}

	return strings.Trim(strings.TrimSpace(string(value)), `"`)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

// SendOTP asks Supabase to send the passwordless Magic Link email template.
// That template can contain either a magic link or the six-digit {{ .Token }}.
func (r *supabaseUserRepository) SendOTP(ctx context.Context, email string) error {
	cleanedEmail := strings.TrimSpace(email)
	payload, err := json.Marshal(map[string]interface{}{
		"email":       cleanedEmail,
		"create_user": false,
	})
	if err != nil {
		return fmt.Errorf("failed to encode magic link or OTP request: %w", err)
	}

	requestURL := strings.TrimRight(r.client.BaseURL, "/") + "/" + supabase.AuthEndpoint + "/otp"
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, requestURL, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("failed to create magic link or OTP request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("apikey", r.authAPIKey)

	response, err := r.client.HTTPClient.Do(request)
	if err != nil {
		return fmt.Errorf("failed to send magic link or OTP to email: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		var authError struct {
			Message string `json:"message"`
			Msg     string `json:"msg"`
		}
		if decodeErr := json.NewDecoder(response.Body).Decode(&authError); decodeErr != nil {
			return fmt.Errorf("failed to send magic link or OTP to email: Supabase returned HTTP %d", response.StatusCode)
		}
		message := authError.Message
		if message == "" {
			message = authError.Msg
		}
		if message == "" {
			message = http.StatusText(response.StatusCode)
		}
		return fmt.Errorf("failed to send magic link or OTP to email: %s", message)
	}

	return nil
}

// VerifyOTP: ตรวจสอบรหัส 6 หลัก
func (r *supabaseUserRepository) VerifyOTP(ctx context.Context, email, otpCode string) (*domain.AuthTokens, error) {

	credentials := supabase.VerifyEmailOtpCredentials{
		Email: email,
		Token: otpCode,
		Type:  supabase.EmailOtpTypeEmail,
	}

	resp, err := r.client.Auth.VerifyOtp(ctx, credentials)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired OTP code: %w", err)
	}

	// ตรวจสอบ Token ชั่วคราวที่ได้กลับมา
	if resp == nil || resp.AccessToken == "" {
		return nil, fmt.Errorf("OTP verified but failed to generate access token")
	}

	return &domain.AuthTokens{
		AccessToken:  resp.AccessToken,
		RefreshToken: resp.RefreshToken,
	}, nil
}

func (r *supabaseUserRepository) IsEmailExists(ctx context.Context, email string) (bool, error) {
	// สร้างตัวแปร Boolean มารองรับผลลัพธ์ขากลับจาก RPC
	var isExists bool

	err := r.client.DB.Rpc("check_email_exists", map[string]interface{}{
		"search_email": strings.TrimSpace(email),
	}).ExecuteWithContext(ctx, &isExists)

	if err != nil {
		return false, fmt.Errorf("rpc query error on check_email_exists: %w", err)
	}

	return isExists, nil
}

func (r *supabaseUserRepository) GetProfile(ctx context.Context, userID string) (*domain.UserProfile, error) {
	var profiles []struct {
		UserID       string `json:"user_id"`
		Email        string `json:"email"`
		UserImageURL string `json:"user_image_url"`
		DisplayName  string `json:"display_name"`
		Bio          string `json:"bio"`
		Username     string `json:"username"`
		Phone        string `json:"phone"`
	}

	err := schemaDatabase(r.client, profilesSchema).From("profile_tb").
		Select("user_id,email,user_image_url,display_name,bio,username,phone").
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &profiles)
	if err != nil {
		return nil, fmt.Errorf("load profile failed: %w", err)
	}

	profile := &domain.UserProfile{UserID: userID}
	if len(profiles) > 0 {
		p := profiles[0]
		profile.Email = p.Email
		profile.UserImageURL = p.UserImageURL
		profile.DisplayName = p.DisplayName
		profile.Bio = p.Bio
		profile.Username = p.Username
		profile.Phone = p.Phone
	}

	user, err := r.client.Admin.GetUser(ctx, userID)
	if err == nil && user != nil {
		if profile.Email == "" {
			profile.Email = user.Email
		}
		if profile.Phone == "" {
			if phone, ok := user.UserMetaData["phone"].(string); ok && phone != "" {
				profile.Phone = phone
			} else {
				profile.Phone = user.Phone
			}
		}
		if profile.DisplayName == "" {
			if dn, ok := user.UserMetaData["display_name"].(string); ok && dn != "" {
				profile.DisplayName = dn
			} else if fn, ok := user.UserMetaData["full_name"].(string); ok && fn != "" {
				profile.DisplayName = fn
			}
		}
		if profile.UserImageURL == "" {
			profile.UserImageURL = googleProfileImageURL(user.UserMetaData)
		}
	}

	return profile, nil
}

func (r *supabaseUserRepository) UpdateProfile(
	ctx context.Context,
	userID string,
	req domain.UpdateProfileRequest,
	img *domain.ProfileImage,
) (*domain.UserProfile, error) {
	fields := make(map[string]interface{})
	metadata := make(map[string]interface{})
	var uploadedPath string

	if req.DisplayName != nil {
		trimmed := strings.TrimSpace(*req.DisplayName)
		fields["display_name"] = trimmed
		metadata["display_name"] = trimmed
	}
	if req.Username != nil {
		fields["username"] = *req.Username
		metadata["username"] = *req.Username
	}
	if req.Bio != nil {
		trimmed := strings.TrimSpace(*req.Bio)
		fields["bio"] = trimmed
		metadata["bio"] = trimmed
	}

	if img != nil {
		objectPath := fmt.Sprintf("%s/profile-%d%s", userID, time.Now().UTC().UnixNano(), img.Extension)
		err := r.uploadProfileImage(ctx, objectPath, img)
		if err != nil {
			return nil, err
		}
		uploadedPath = objectPath
		publicURL := r.storage.publicURL(profileBucket, objectPath)
		fields["user_image_url"] = publicURL
		metadata["avatar_url"] = publicURL
	}

	if len(fields) > 0 {
		var updated []map[string]interface{}
		err := schemaDatabase(r.client, profilesSchema).From("profile_tb").
			Update(fields).
			Eq("user_id", userID).
			ExecuteWithContext(ctx, &updated)
		if err != nil {
			if uploadedPath != "" {
				r.removeProfileImage(ctx, uploadedPath)
			}
			var requestErr *postgrest.RequestError
			if errors.As(err, &requestErr) {
				switch {
				case requestErr.Code == "23505" && strings.Contains(requestErr.Message, "profile_tb_username_ci_key"):
					return nil, domain.ErrUsernameTaken
				case requestErr.Code == "P0001" && requestErr.Message == domain.ErrUsernameChangeCooldown.Error():
					return nil, domain.ErrUsernameChangeCooldown
				}
			}
			return nil, fmt.Errorf("update profile_tb failed: %w", err)
		}
		if img != nil && len(updated) == 0 {
			r.removeProfileImage(ctx, uploadedPath)
			return nil, fmt.Errorf("profile row was not found for image update")
		}
	}

	if len(metadata) > 0 {
		_, _ = r.client.Admin.UpdateUser(ctx, userID, supabase.AdminUserParams{
			UserMetadata: metadata,
		})
	}

	return r.GetProfile(ctx, userID)
}

func (r *supabaseUserRepository) UpdateContact(ctx context.Context, userID string, phone string) error {
	normalizedPhone := strings.TrimSpace(phone)
	fields := map[string]interface{}{
		"phone": normalizedPhone,
	}

	var updated []map[string]interface{}
	err := schemaDatabase(r.client, profilesSchema).From("profile_tb").
		Update(fields).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return fmt.Errorf("update contact in profile_tb failed: %w", err)
	}
	if len(updated) == 0 {
		return fmt.Errorf("profile was not found for contact update")
	}

	_, _ = r.client.Admin.UpdateUser(ctx, userID, supabase.AdminUserParams{
		Phone: normalizedPhone,
		UserMetadata: map[string]interface{}{
			"phone": normalizedPhone,
		},
	})

	return nil
}
