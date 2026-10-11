package supabase

import (
	"context"
	"io"
	"log"
	"net/http"

	"github.com/nedpals/supabase-go"
)

// InitSupabaseClient ทำหน้าที่ตรวจสอบความถูกต้องและสร้าง Client ของ Supabase
func InitSupabaseClient(url, anonKey string) *supabase.Client {
	if url == "" || anonKey == "" {
		log.Fatalf("Supabase URL or Anon Key is empty! please check .env")
	}

	// สร้างตัวเชื่อมต่อหลัก
	client := supabase.CreateClient(url, anonKey)
	transport := http.DefaultTransport
	if standard, ok := transport.(*http.Transport); ok {
		pool := standard.Clone()
		pool.MaxIdleConns = 100
		pool.MaxIdleConnsPerHost = 20
		transport = pool
	}
	client.HTTPClient = &http.Client{Transport: transport, Timeout: supabaseRequestTimeout}
	// PostgREST ซ่อน HTTP client ไว้ จึงจำกัดเวลาตั้งแต่เริ่มส่งจนอ่าน response body จบ
	client.DB.Transport.Parent = timeoutTransport{base: transport}

	log.Println("Connection to Supabase Client success!")
	return client
}

type timeoutTransport struct {
	base http.RoundTripper
}

func (t timeoutTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	ctx, cancel := context.WithTimeout(request.Context(), supabaseRequestTimeout)
	response, err := t.base.RoundTrip(request.Clone(ctx))
	if err != nil {
		cancel()
		return nil, err
	}
	response.Body = &cancelResponseBody{ReadCloser: response.Body, cancel: cancel}
	return response, nil
}

type cancelResponseBody struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (b *cancelResponseBody) Close() error {
	defer b.cancel()
	return b.ReadCloser.Close()
}
