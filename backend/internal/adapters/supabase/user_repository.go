package supabase

import (
	"context"
	"fmt"
	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	"strings"
)

type SupabaseUserRepository struct {
	client *supabase.Client
}

func NewSupabaseUserRepository(sbClient *supabase.Client) domain.AuthRepository {
	return &SupabaseUserRepository{
		client: sbClient,
	}
}

// Login ตรวจสอบสิทธิ์ผ่าน Supabase Auth และส่ง Access Token กลับออกไป
func (r *SupabaseUserRepository) Login(ctx context.Context, email, password string) (string, error) {
	// 1. เรียกใช้ client.Auth ให้ถูกจุด และส่ง UserCredentials
	resp, err := r.client.Auth.SignIn(ctx, supabase.UserCredentials{
		Email:    email,
		Password: password,
	})
	if err != nil {
		return "", fmt.Errorf("supabase login failed: %w", err)
	}

	// 2. ตรวจสอบว่าได้ Token กลับมาจริงไหม ป้องกันกรณีเกิดความผิดพลาดภายใน
	if resp.AccessToken == "" {
		return "", fmt.Errorf("authentication succeeded but no access token returned")
	}

	// 3. คืนค่า AccessToken กลับไป (ตรงตาม signature string, error)
	return resp.AccessToken, nil
}

// Register สร้างบัญชีผู้ใช้ใหม่ผ่าน Supabase Auth และส่ง Access Token กลับออกไป
func (r *SupabaseUserRepository) Register(ctx context.Context, email, password string) (string, error) {
	resp, err := r.client.Auth.SignUp(ctx, supabase.UserCredentials{
		Email:    email,
		Password: password,
	})

	if err != nil {
		// ดักจับ Error ที่เกิดจากการพยายามลงทะเบียนด้วยอีเมลที่มีอยู่แล้วในระบบ
		if strings.Contains(strings.ToLower(err.Error()), "already registered") ||
			strings.Contains(strings.ToLower(err.Error()), "already exists") {
			return "", fmt.Errorf("email already registered") // ส่ง Error Code เฉพาะของเรากลับไป
		}

		return "", fmt.Errorf("supabase registration failed: %w", err)
	}

	// ป้องกันกรณีที่ Supabase ส่งค่ากลับมาเป็น nil
	if resp == nil {
		return "", fmt.Errorf("registration succeeded but response is nil")
	}
	if resp.ID == "" {
		// ถ้าหา ID ไม่เจอจริงๆ แต่ไม่มี error ให้ลองสืบค้นผ่านฟิลด์อื่น
		return "REGISTRATION_SUCCESS_PENDING_CONFIRMATION", nil
	}
	// คืนค่า User.ID (string) กลับไปแทน เพื่อยืนยันว่าสร้างบัญชีบน Supabase สำเร็จแล้ว
	return resp.ID, nil
}

// ChangePassword เปลี่ยนรหัสผ่านของผู้ใช้ผ่าน Supabase Auth
func (r *SupabaseUserRepository) ChangePassword(ctx context.Context, userToken, newPassword string) error {
	updateData := map[string]interface{}{
		"password": newPassword,
	}
	_, err := r.client.Auth.UpdateUser(ctx, userToken, updateData)
	if err != nil {
		return fmt.Errorf("supabase update password failed: %w", err)
	}

	return nil
}

// RequestResetOTP: สั่งให้ Supabase ส่งรหัส OTP 8 หลักไปที่อีเมลของผู้ใช้
func (r *SupabaseUserRepository) RequestResetOTP(ctx context.Context, email string) error {
	cleanedEmail := strings.TrimSpace(email)

	err := r.client.Auth.ResetPasswordForEmail(ctx, cleanedEmail, "")
	if err != nil {
		return fmt.Errorf("failed to send reset OTP to email: %w", err)
	}

	return nil
}

// VerifyOTP: ตรวจสอบรหัส 8 หลัก
func (r *SupabaseUserRepository) VerifyOTP(ctx context.Context, email, otpCode string) error {

	credentials := supabase.VerifyEmailOtpCredentials{
		Email: email,
		Token: otpCode,
		Type:  "recovery",
	}

	resp, err := r.client.Auth.VerifyOtp(ctx, credentials)
	if err != nil {
		return fmt.Errorf("invalid or expired OTP code: %w", err)
	}

	// ตรวจสอบ Token ชั่วคราวที่ได้กลับมา
	if resp == nil || resp.AccessToken == "" {
		return fmt.Errorf("OTP verified but failed to generate access token")
	}

	return nil
}

func (r *SupabaseUserRepository) IsEmailExists(ctx context.Context, email string) (bool, error) {
	// สร้างตัวแปร Boolean มารองรับผลลัพธ์ขากลับจาก RPC
	var isExists bool

	err := r.client.DB.Rpc("check_email_exists", map[string]interface{}{
		"search_email": strings.TrimSpace(email),
	}).Execute(&isExists)

	if err != nil {
		return false, fmt.Errorf("rpc query error on check_email_exists: %w", err)
	}

	return isExists, nil
}

// Logout ออกจากระบบโดยการลบ Session ผ่าน Supabase Auth
func (r *SupabaseUserRepository) Logout(ctx context.Context, accessToken string) error {
	err := r.client.Auth.SignOut(ctx, accessToken)
	if err != nil {
		return fmt.Errorf("supabase logout failed: %w", err)
	}

	return nil
}
