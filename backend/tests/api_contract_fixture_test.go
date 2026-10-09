package tests

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
)

const contractBearer = "test-bearer"
const contractAppKey = "test-app-key"
const contractPrivateDetail = "private-database-detail"
const contractSSE = "event: token\ndata: {\"text\":\"hello\"}\n\nevent: done\ndata: {}\n\n"

// จำลองเฉพาะพอร์ตภายนอก แต่ส่งทุกคำขอผ่าน router และ middleware ของระบบจริง
type apiContractFixture struct {
	t           *testing.T
	errors      map[string]error
	calls       map[string]int
	args        map[string][]any
	userID      string
	emailExists bool
	profile     *domain.UserProfile
	items       []domain.RankedItem
	pushes      chan domain.ChatPushNotification
	pushError   error
}

func newAPIContractFixture(t *testing.T) *apiContractFixture {
	return &apiContractFixture{
		t: t, errors: map[string]error{}, calls: map[string]int{}, args: map[string][]any{},
		userID: "verified-user", emailExists: true,
		profile: &domain.UserProfile{UserID: "verified-user", Email: "fixture@example.test", DisplayName: "Verified name", UserImageURL: "https://example.test/avatar.png"},
		items:   []domain.RankedItem{{Item: domain.Item{ID: 7, UserID: "owner", ItemName: "Camera", Category: "Camera", Description: "Digital camera", Price: 100, Status: "available", Type: "daily"}, Rating: 4.5, ReviewCount: 2, PaidBookingCount: 3}},
		pushes:  make(chan domain.ChatPushNotification, 1),
	}
}

func (f *apiContractFixture) app() *fiber.App {
	return ports.SetupRouter(f, f, f, f, f, f, contractAppKey)
}

func (f *apiContractFixture) record(ctx context.Context, op string, args ...any) error {
	f.t.Helper()
	require.NotNil(f.t, ctx)
	require.NoError(f.t, ctx.Err(), "context ถูกยกเลิกก่อนเรียก adapter: %s", op)
	f.calls[op]++
	f.args[op] = args
	return f.errors[op]
}

func (f *apiContractFixture) UserIDFromToken(ctx context.Context, token string) (string, error) {
	if err := f.record(ctx, "verify", token); err != nil {
		return "", err
	}
	if token != contractBearer {
		return "", errors.New("invalid access token")
	}
	return f.userID, nil
}

func (f *apiContractFixture) Login(ctx context.Context, email, password string) (*domain.AuthTokens, error) {
	err := f.record(ctx, "login", email, password)
	return &domain.AuthTokens{AccessToken: "test-access", RefreshToken: "test-refresh"}, err
}

func (f *apiContractFixture) Register(ctx context.Context, user domain.RegisterUser) (*domain.RegisterResult, error) {
	err := f.record(ctx, "register", user)
	return &domain.RegisterResult{UserID: "registered-user", UserImageURL: "https://example.test/profile.png"}, err
}

func (f *apiContractFixture) SyncGoogleProfileImage(ctx context.Context, token string) (string, error) {
	err := f.record(ctx, "google", token)
	if token != contractBearer {
		return "", errors.New("invalid access token")
	}
	return "https://example.test/google.png", err
}

func (f *apiContractFixture) ChangePassword(ctx context.Context, token, password string) error {
	err := f.record(ctx, "password", token, password)
	if token != contractBearer {
		return domain.ErrInvalidAccessToken
	}
	return err
}

func (f *apiContractFixture) SendOTP(ctx context.Context, email string) error {
	return f.record(ctx, "sendOTP", email)
}

func (f *apiContractFixture) VerifyOTP(ctx context.Context, email, otp string) (*domain.AuthTokens, error) {
	err := f.record(ctx, "verifyOTP", email, otp)
	return &domain.AuthTokens{AccessToken: "test-access", RefreshToken: "test-refresh"}, err
}

func (f *apiContractFixture) IsEmailExists(ctx context.Context, email string) (bool, error) {
	return f.emailExists, f.record(ctx, "emailExists", email)
}

func (f *apiContractFixture) GetProfile(ctx context.Context, userID string) (*domain.UserProfile, error) {
	return f.profile, f.record(ctx, "profile", userID)
}

func (f *apiContractFixture) UpdateProfile(ctx context.Context, userID string, request domain.UpdateProfileRequest, image *domain.ProfileImage) (*domain.UserProfile, error) {
	return f.profile, f.record(ctx, "updateProfile", userID, request, image)
}

func (f *apiContractFixture) UpdateContact(ctx context.Context, userID, phone string) error {
	return f.record(ctx, "contact", userID, phone)
}

func (f *apiContractFixture) UpdateFCMToken(ctx context.Context, userID, token string) error {
	return f.record(ctx, "fcm", userID, token)
}

func (f *apiContractFixture) GetFCMToken(ctx context.Context, userID string) (string, error) {
	return "test-device", f.record(ctx, "getFCM", userID)
}

func (f *apiContractFixture) DeleteFCMToken(ctx context.Context, userID string) error {
	return f.record(ctx, "deleteFCM", userID)
}

func (f *apiContractFixture) Insert(ctx context.Context, item *domain.Item, images []domain.ItemImage) (*domain.Item, error) {
	err := f.record(ctx, "insertItem", *item, images)
	item.ID = 7
	return item, err
}

func (f *apiContractFixture) FindAll(ctx context.Context) ([]domain.RankedItem, error) {
	return f.items, f.record(ctx, "items")
}

func (f *apiContractFixture) FindByID(ctx context.Context, id int64) (*domain.Item, error) {
	return &f.items[0].Item, f.record(ctx, "item", id)
}

func (f *apiContractFixture) Update(ctx context.Context, id int64, userID string, fields map[string]interface{}) (*domain.Item, error) {
	return &f.items[0].Item, f.record(ctx, "updateItem", id, userID, fields)
}

func (f *apiContractFixture) Delete(ctx context.Context, id int64, userID string) error {
	return f.record(ctx, "deleteItem", id, userID)
}

func (f *apiContractFixture) CreateRental(ctx context.Context, userID string, request domain.CreateRentalRequest) (*domain.RentalOrder, error) {
	err := f.record(ctx, "rental", userID, request)
	return &domain.RentalOrder{ID: 9, UserID: userID, ItemID: request.ItemID, StartAt: request.StartAt, EndAt: request.EndAt, RentalType: request.RentalType, PickupLocation: request.PickupLocation, TotalPrice: 200, Status: "pending"}, err
}

func (f *apiContractFixture) UpdateRentalStatus(ctx context.Context, userID string, id int64, status string) (*domain.RentalOrder, error) {
	err := f.record(ctx, "rentalStatus", userID, id, status)
	return &domain.RentalOrder{ID: id, UserID: userID, Status: status}, err
}

func (f *apiContractFixture) PhoneForConversation(ctx context.Context, userID, conversationID string) (string, error) {
	return "+66812345678", f.record(ctx, "chatContact", userID, conversationID)
}

func (f *apiContractFixture) SendChatPush(ctx context.Context, notification domain.ChatPushNotification) error {
	// goroutine ส่งผลผ่าน channel เพื่อรออย่างแน่นอนโดยไม่ใช้ sleep หรืออ่าน map ข้าม goroutine
	f.pushes <- notification
	return f.pushError
}

func (f *apiContractFixture) SendMessage(ctx context.Context, request domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
	err := f.record(ctx, "ai", request)
	return &domain.ChatbotResponse{Status: "success", Answer: "hello", RecommendedItems: []domain.RecommendedItem{}, Questions: []domain.ClarificationQuestion{}, SuggestedReplies: []string{}}, err
}

func (f *apiContractFixture) SendMessageStream(ctx context.Context, request domain.ChatbotRequest) (io.ReadCloser, error) {
	err := f.record(ctx, "stream", request)
	return io.NopCloser(strings.NewReader(contractSSE)), err
}
