package domain

import (
	"context"
	"io"
)

// ChatMessageItem ข้อมูลข้อความในประวัติการสนทนาระหว่างผู้ใช้กับ AI (Stateless History)
type ChatMessageItem struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatbotRequest คำขอสนทนาจาก Client ที่ส่งข้อความและประวัติการคุยแบบ Sliding Window
type ChatbotRequest struct {
	Query     string            `json:"query"`
	Message   string            `json:"message"`
	SessionID string            `json:"session_id,omitempty"`
	History   []ChatMessageItem `json:"history"`
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
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	ItemName    string  `json:"item_name,omitempty"`
	Category    string  `json:"category"`
	Price       float64 `json:"price"`
	PriceUnit   string  `json:"price_unit"`
	Unit        string  `json:"unit,omitempty"`
	Status      string  `json:"status"`
	ImageURL    string  `json:"image_url"`
	Description string  `json:"description"`
}

// ClarificationQuestion คำถามถามกลับเพื่อช่วยระบุความต้องการให้ชัดเจนขึ้น
type ClarificationQuestion struct {
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
	Status           string                  `json:"status"`
	Answer           string                  `json:"answer"`
	RecommendedItems []RecommendedItem       `json:"recommended_items"`
	Questions        []ClarificationQuestion `json:"questions"`
	SuggestedReplies []string                `json:"suggested_replies"`
	Thought          string                  `json:"thought,omitempty"`
	SearchQuery      string                  `json:"search_query,omitempty"`
	SearchSources    []SearchSource          `json:"search_sources,omitempty"`
	Activities       []string                `json:"activities,omitempty"`
}

// AIChatbotGateway สัญญา (Port) สำหรับติดต่อกับระบบภายนอก AI Service
type AIChatbotGateway interface {
	// SendMessage ส่งข้อความเพื่อรับคำตอบแบบสมบูรณ์ก้อนเดียว (Non-Streaming)
	SendMessage(ctx context.Context, req ChatbotRequest) (*ChatbotResponse, error)
	// SendMessageStream ส่งข้อความเพื่อรับสตรีมคำตอบแบบพิมพ์ดีด (Server-Sent Events)
	SendMessageStream(ctx context.Context, req ChatbotRequest) (io.ReadCloser, error)
}
