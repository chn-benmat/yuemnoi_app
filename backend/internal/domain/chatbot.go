package domain

import (
	"context"
	"fmt"
	"io"
)

// AIServiceError ส่งเฉพาะสถานะและรหัสที่ปลอดภัย ไม่ส่งข้อความภายในจากผู้ให้บริการ
type AIServiceError struct {
	StatusCode        int
	Code              string
	RetryAfterSeconds *int
}

func (e *AIServiceError) Error() string {
	return fmt.Sprintf("ai service unavailable (status %d)", e.StatusCode)
}

// ChatMessageItem ข้อมูลข้อความในประวัติการสนทนาระหว่างผู้ใช้กับ AI (Stateless History)
type ChatMessageItem struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatbotRequest คำขอสนทนาจาก Client ที่ส่งข้อความและประวัติการคุยแบบ Sliding Window
type ChatbotRequest struct {
	Query                string                `json:"query"`
	Message              string                `json:"message"`
	SessionID            string                `json:"session_id,omitempty"`
	History              []ChatMessageItem     `json:"history"`
	Context              *ChatSessionContext   `json:"context,omitempty"`
	QuestionnaireAnswers []QuestionnaireAnswer `json:"questionnaire_answers,omitempty"`
	QuestionnaireSkipped bool                  `json:"questionnaire_skipped,omitempty"`
	ActiveQuestionID     *string               `json:"active_question_id,omitempty"`
}

// EffectiveMessage คืนค่าข้อความคำถามจาก Query หรือ Message
func (r *ChatbotRequest) EffectiveMessage() string {
	if r.Query != "" {
		return r.Query
	}
	return r.Message
}

// RecommendedItem ข้อมูลสินค้าที่ AI แนะนำให้เช่า
type RecommendedItem struct {
	PriceDisplay  string  `json:"price_display,omitempty"`
	UnitDisplay   string  `json:"unit_display,omitempty"`
	StatusDisplay string  `json:"status_display,omitempty"`
	ID            string  `json:"id"`
	Name          string  `json:"name"`
	ItemName      string  `json:"item_name,omitempty"`
	Category      string  `json:"category"`
	Price         float64 `json:"price"`
	PriceUnit     string  `json:"price_unit"`
	Unit          string  `json:"unit,omitempty"`
	Status        string  `json:"status"`
	ImageURL      string  `json:"image_url"`
	Description   string  `json:"description"`
}

// ClarificationQuestion คำถามถามกลับเพื่อช่วยระบุความต้องการให้ชัดเจนขึ้น
type ClarificationQuestion struct {
	Dimension      string              `json:"dimension,omitempty"`
	Choices        []QuestionChoice    `json:"choices,omitempty"`
	ID             string              `json:"id"`
	Title          string              `json:"title"`
	Options        []string            `json:"options"`
	Step           int                 `json:"step,omitempty"`
	TotalSteps     int                 `json:"total_steps,omitempty"`
	SelectedOption string              `json:"selected_option,omitempty"`
	BranchTitles   map[string]string   `json:"branch_titles,omitempty"`
	BranchOptions  map[string][]string `json:"branch_options,omitempty"`
}

// SearchSource ข้อมูลแหล่งอ้างอิงเว็บไซต์ที่ได้จากการค้นหาทางอินเทอร์เน็ต
type SearchSource struct {
	Title   string `json:"title"`
	URL     string `json:"url"`
	Domain  string `json:"domain"`
	Snippet string `json:"snippet,omitempty"`
}

// ChatbotResponse ข้อมูลผลลัพธ์ตอบกลับจาก AI Service สำหรับแสดงผลบน Client
type ChatbotResponse struct {
	RequestScope          *string                 `json:"request_scope,omitempty"`
	InformationSufficient *bool                   `json:"information_sufficient,omitempty"`
	NextAction            *string                 `json:"next_action,omitempty"`
	ResponseFlow          *string                 `json:"response_flow,omitempty"`
	ResponseKind          *string                 `json:"response_kind,omitempty"`
	Context               *ChatSessionContext     `json:"context,omitempty"`
	References            []EvidenceReference     `json:"references,omitempty"`
	Status                string                  `json:"status"`
	Answer                string                  `json:"answer"`
	RecommendedItems      []RecommendedItem       `json:"recommended_items"`
	Questions             []ClarificationQuestion `json:"questions"`
	SuggestedReplies      []string                `json:"suggested_replies"`
	Thought               string                  `json:"thought,omitempty"`
	SearchQuery           string                  `json:"search_query,omitempty"`
	SearchSources         []SearchSource          `json:"search_sources,omitempty"`
	Activities            []string                `json:"activities,omitempty"`
}

// QuestionChoice เก็บรหัสตัวเลือกแยกจากข้อความที่แสดง
type QuestionChoice struct {
	ID          string `json:"id"`
	Label       string `json:"label"`
	Description string `json:"description,omitempty"`
	ActionValue string `json:"action_value"`
}

// ConversationFact เป็นข้อมูลผู้ใช้ในแชต ไม่ใช่หลักฐานราคา สต็อก หรือนโยบาย
type ConversationFact struct {
	Dimension        string   `json:"dimension"`
	Value            string   `json:"value"`
	SourceMessageIDs []string `json:"source_message_ids"`
}

// ChatSessionContext ส่งต่อเฉพาะบริบทของแชตปัจจุบัน
type ChatSessionContext struct {
	BudgetMax             *float64                `json:"budget_max,omitempty"`
	BudgetUnit            *string                 `json:"budget_unit,omitempty"`
	IntendedUse           *string                 `json:"intended_use,omitempty"`
	Categories            []string                `json:"categories,omitempty"`
	TargetItems           []string                `json:"target_items,omitempty"`
	SessionID             string                  `json:"session_id"`
	UserGoal              string                  `json:"user_goal"`
	KnownFacts            []ConversationFact      `json:"known_facts,omitempty"`
	UserConstraints       []ConversationFact      `json:"user_constraints,omitempty"`
	ExcludedItems         []string                `json:"excluded_items,omitempty"`
	ReferencedItemIDs     []string                `json:"referenced_item_ids,omitempty"`
	ClarificationDeclined bool                    `json:"clarification_declined"`
	Questions             []ClarificationQuestion `json:"questions,omitempty"`
}

// QuestionnaireAnswer จับคู่คำตอบกับคำถามด้วยรหัส
type QuestionnaireAnswer struct {
	QuestionID string  `json:"question_id"`
	OptionID   *string `json:"option_id,omitempty"`
	Text       *string `json:"text,omitempty"`
}

// EvidenceReference แหล่งอ้างอิงที่ตรวจสอบโดย AI Service
type EvidenceReference struct {
	ID            string  `json:"id"`
	Kind          string  `json:"kind"`
	Title         string  `json:"title"`
	Reference     string  `json:"reference"`
	ReviewedAt    *string `json:"reviewed_at,omitempty"`
	ContentSHA256 *string `json:"content_sha256,omitempty"`
}

// AIChatbotGateway สัญญา (Port) สำหรับติดต่อกับระบบภายนอก AI Service
type AIChatbotGateway interface {
	// SendMessage ส่งข้อความเพื่อรับคำตอบแบบสมบูรณ์ก้อนเดียว (Non-Streaming)
	SendMessage(ctx context.Context, req ChatbotRequest) (*ChatbotResponse, error)
	// SendMessageStream ส่งข้อความเพื่อรับสตรีมคำตอบแบบพิมพ์ดีด (Server-Sent Events)
	SendMessageStream(ctx context.Context, req ChatbotRequest) (io.ReadCloser, error)
}
