package supabase

import (
	"net/url"
	"strings"

	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

const (
	messagingSchema = "messaging"
	profilesSchema  = "profiles"
)

// แยก headers ของแต่ละคำขอ โดยใช้ connection pool และ timeout เดิมร่วมกัน
// เพื่อไม่ให้คำขอคนละ schema เปลี่ยน headers ของ client ที่ใช้งานพร้อมกัน
func schemaDatabase(client *supabase.Client, schema string) *postgrest.Client {
	endpoint, err := url.Parse(strings.TrimRight(client.BaseURL, "/") + "/rest/v1/")
	if err != nil {
		panic(err)
	}
	database := postgrest.NewClient(*endpoint, func(database *postgrest.Client) {
		for name, values := range client.DB.Headers() {
			for _, value := range values {
				database.AddHeader(name, value)
			}
		}
	}, postgrest.WithSchema(schema))
	database.Transport.Parent = client.DB.Transport.Parent
	return database
}
