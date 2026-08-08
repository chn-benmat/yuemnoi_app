package ports

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type authRepositoryStub struct {
	verifiedEmail string
	verifiedOTP   string
}

func (s *authRepositoryStub) Login(context.Context, string, string) (string, error) {
	return "", nil
}

func (s *authRepositoryStub) Register(context.Context, string, string) (string, error) {
	return "", nil
}

func (s *authRepositoryStub) ChangePassword(context.Context, string, string) error {
	return nil
}

func (s *authRepositoryStub) RequestResetOTP(context.Context, string) error {
	return nil
}

func (s *authRepositoryStub) VerifyOTP(_ context.Context, email, otpCode string) error {
	s.verifiedEmail = email
	s.verifiedOTP = otpCode
	return nil
}

func (s *authRepositoryStub) IsEmailExists(context.Context, string) (bool, error) {
	return true, nil
}

func (s *authRepositoryStub) Logout(context.Context, string) error {
	return nil
}

func TestVerifyResetOTPAcceptsBodyWithoutNewPassword(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := &authRepositoryStub{}
	handler := NewUserHandler(repo)
	router := gin.New()
	router.POST("/api/v1/auth/verify-reset-otp", handler.VerifyResetOTP)

	body := []byte(`{"email":"user@example.com","otp_code":"123456"}`)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/verify-reset-otp", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, response.Code, response.Body.String())
	}
	if repo.verifiedEmail != "user@example.com" {
		t.Fatalf("expected email to be forwarded, got %q", repo.verifiedEmail)
	}
	if repo.verifiedOTP != "123456" {
		t.Fatalf("expected OTP to be forwarded, got %q", repo.verifiedOTP)
	}
}
