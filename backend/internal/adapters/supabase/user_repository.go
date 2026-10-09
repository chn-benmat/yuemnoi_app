package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
)

const profileBucket = "profile_bk"

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
	user, err := r.client.Auth.User(ctx, userToken)
	if err != nil {
		return "", fmt.Errorf("invalid access token: %w", err)
	}
	if user == nil || user.ID == "" {
		return "", fmt.Errorf("access token does not contain a user")
	}

	return user.ID, nil
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
	err = r.client.DB.From("profile_tb").
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

// Register creates the Auth user, uploads an optional profile image, and stores
// its public URL in profile_tb.
func (r *supabaseUserRepository) Register(ctx context.Context, user domain.RegisterUser) (*domain.RegisterResult, error) {
	emailExists, err := r.IsEmailExists(ctx, user.Email)
	if err != nil {
		return nil, fmt.Errorf("failed to check whether email is already registered: %w", err)
	}
	if emailExists {
		return nil, fmt.Errorf("email already registered")
	}

	password := user.Password
	resp, err := r.client.Admin.CreateUser(ctx, supabase.AdminUserParams{
		Email:        user.Email,
		Phone:        user.Phone,
		Password:     &password,
		EmailConfirm: true,
		PhoneConfirm: true,
		UserMetadata: supabase.JSONMap{
			"display_name": user.DisplayName,
			"phone":        user.Phone,
		},
	})

	if err != nil {
		// ดักจับ Error ที่เกิดจากการพยายามลงทะเบียนด้วยอีเมลที่มีอยู่แล้วในระบบ
		if strings.Contains(strings.ToLower(err.Error()), "already registered") ||
			strings.Contains(strings.ToLower(err.Error()), "already exists") {
			return nil, fmt.Errorf("email already registered") // ส่ง Error Code เฉพาะของเรากลับไป
		}

		return nil, fmt.Errorf("supabase registration failed: %w", err)
	}

	if resp == nil || resp.ID == "" {
		return nil, fmt.Errorf("registration succeeded but no user ID returned")
	}

	return r.completeRegistration(ctx, user, resp.ID)
}

func (r *supabaseUserRepository) completeRegistration(ctx context.Context, user domain.RegisterUser, userID string) (*domain.RegisterResult, error) {
	result := &domain.RegisterResult{UserID: userID}
	if user.ProfileImage == nil {
		return result, nil
	}

	objectPath := fmt.Sprintf("profile-%s-%d%s", userID, time.Now().UTC().UnixNano(), user.ProfileImage.Extension)
	err := r.uploadProfileImage(ctx, objectPath, user.ProfileImage)
	if err != nil {
		return nil, err
	}

	publicURL := r.storage.publicURL(profileBucket, objectPath)

	var updated []map[string]interface{}
	err = r.client.DB.From("profile_tb").
		Update(map[string]interface{}{"user_image_url": publicURL}).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		r.removeProfileImage(ctx, objectPath)
		return nil, fmt.Errorf("failed to save profile image URL: %w", err)
	}
	if len(updated) == 0 {
		r.removeProfileImage(ctx, objectPath)
		return nil, fmt.Errorf("profile row was not created for the registered user")
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
	err := r.client.DB.From("profile_tb").Select("user_id").
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

	err := r.client.DB.From("profile_tb").
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
		trimmed := strings.TrimSpace(*req.Username)
		fields["username"] = trimmed
		metadata["username"] = trimmed
	}
	if req.Bio != nil {
		trimmed := strings.TrimSpace(*req.Bio)
		fields["bio"] = trimmed
		metadata["bio"] = trimmed
	}

	if img != nil {
		objectPath := fmt.Sprintf("profile-%s-%d%s", userID, time.Now().UTC().UnixNano(), img.Extension)
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
		err := r.client.DB.From("profile_tb").
			Update(fields).
			Eq("user_id", userID).
			ExecuteWithContext(ctx, &updated)
		if err != nil {
			if uploadedPath != "" {
				r.removeProfileImage(ctx, uploadedPath)
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
	err := r.client.DB.From("profile_tb").
		Update(fields).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return fmt.Errorf("update contact in profile_tb failed: %w", err)
	}

	_, _ = r.client.Admin.UpdateUser(ctx, userID, supabase.AdminUserParams{
		Phone: normalizedPhone,
		UserMetadata: map[string]interface{}{
			"phone": normalizedPhone,
		},
	})

	return nil
}

func (r *supabaseUserRepository) UpdateFCMToken(ctx context.Context, userID string, fcmToken string) error {
	fields := map[string]interface{}{
		"fcm_token": strings.TrimSpace(fcmToken),
	}

	var updated []map[string]interface{}
	err := r.client.DB.From("profile_tb").
		Update(fields).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return fmt.Errorf("update fcm token in profile_tb failed: %w", err)
	}

	return nil
}

// GetFCMToken ดึง fcm_token ของผู้ใช้จาก profile_tb
func (r *supabaseUserRepository) GetFCMToken(ctx context.Context, userID string) (string, error) {
	var rows []struct {
		FCMToken string `json:"fcm_token"`
	}

	err := r.client.DB.From("profile_tb").
		Select("fcm_token").
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &rows)
	if err != nil {
		return "", fmt.Errorf("load fcm token failed: %w", err)
	}
	if len(rows) == 0 {
		return "", nil
	}

	return strings.TrimSpace(rows[0].FCMToken), nil
}

// DeleteFCMToken ล้าง fcm_token ที่ไม่สามารถใช้งานได้ออกจาก profile_tb
func (r *supabaseUserRepository) DeleteFCMToken(ctx context.Context, userID string) error {
	fields := map[string]interface{}{
		"fcm_token": nil,
	}

	var updated []map[string]interface{}
	err := r.client.DB.From("profile_tb").
		Update(fields).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return fmt.Errorf("delete fcm token failed: %w", err)
	}

	return nil
}
