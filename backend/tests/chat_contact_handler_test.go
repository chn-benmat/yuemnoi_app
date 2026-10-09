package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
)

type chatContactRepository struct {
	phone          string
	err            error
	requesterID    string
	conversationID string
}

func (r *chatContactRepository) PhoneForConversation(
	_ context.Context,
	requesterID string,
	conversationID string,
) (string, error) {
	r.requesterID = requesterID
	r.conversationID = conversationID
	return r.phone, r.err
}

type chatContactTokenVerifier struct {
	userID string
	err    error
}

func (v chatContactTokenVerifier) UserIDFromToken(context.Context, string) (string, error) {
	return v.userID, v.err
}

func TestGetConversationContactReturnsParticipantPhone(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repository := &chatContactRepository{phone: "0812345678"}
	handler := ports.NewChatContactHandler(
		repository,
		chatContactTokenVerifier{userID: "requester-1"},
	)
	router := gin.New()
	router.POST("/api/chat/contact", handler.GetConversationContact)

	body, err := json.Marshal(map[string]string{"conversation_id": "conversation-1"})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/chat/contact",
		bytes.NewReader(body),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d: %s", response.Code, response.Body.String())
	}
	if repository.requesterID != "requester-1" || repository.conversationID != "conversation-1" {
		t.Fatalf("unexpected repository arguments: %#v", repository)
	}
	if response.Body.String() != `{"phone":"0812345678"}` {
		t.Fatalf("unexpected response body: %s", response.Body.String())
	}
}

func TestGetConversationContactMapsForbiddenError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := ports.NewChatContactHandler(
		&chatContactRepository{err: domain.ErrContactForbidden},
		chatContactTokenVerifier{userID: "requester-1"},
	)
	router := gin.New()
	router.POST("/api/chat/contact", handler.GetConversationContact)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/chat/contact",
		bytes.NewBufferString(`{"conversation_id":"conversation-1"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("expected status 403, got %d: %s", response.Code, response.Body.String())
	}
}

func TestGetConversationContactRejectsInvalidToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := ports.NewChatContactHandler(
		&chatContactRepository{},
		chatContactTokenVerifier{err: errors.New("invalid token")},
	)
	router := gin.New()
	router.POST("/api/chat/contact", handler.GetConversationContact)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/chat/contact",
		bytes.NewBufferString(`{"conversation_id":"conversation-1"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer invalid-token")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d: %s", response.Code, response.Body.String())
	}
}
