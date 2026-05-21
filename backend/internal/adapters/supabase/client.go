package supabase

import (
	"github.com/nedpals/supabase-go"
	"log"
)

// InitSupabaseClient ทำหน้าที่ตรวจสอบความถูกต้องและสร้าง Client ของ Supabase
func InitSupabaseClient(url, anonKey string) *supabase.Client {
	if url == "" || anonKey == "" {
		log.Fatalf("Supabase URL or Anon Key is empty! please check .env")
	}

	// สร้างตัวเชื่อมต่อหลัก
	client := supabase.CreateClient(url, anonKey)

	log.Println("Connection to Supabase Client success!")
	return client
}
