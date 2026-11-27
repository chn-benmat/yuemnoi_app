package emaildns

import (
	"context"
	"errors"
	"net"
	"strings"
	"time"

	"golang.org/x/net/idna"
)

type Resolver interface {
	LookupMX(ctx context.Context, name string) ([]*net.MX, error)
	LookupHost(ctx context.Context, name string) ([]string, error)
}

type Checker struct {
	resolver Resolver
}

func NewChecker(resolver Resolver) Checker {
	return Checker{resolver: resolver}
}

func (c Checker) IsUndeliverable(ctx context.Context, name string) bool {
	ascii, err := idna.Lookup.ToASCII(name)
	if err != nil {
		return true
	}
	fqdn := strings.TrimSuffix(ascii, ".") + "."
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	mx, err := c.resolver.LookupMX(ctx, fqdn)
	if len(mx) > 0 {
		// Null MX ประกาศว่าโดเมนไม่รับเมล แม้จะมี IP สำหรับเว็บไซต์
		return err == nil && len(mx) == 1 && mx[0].Host == "." && mx[0].Pref == 0
	}
	if err != nil && !isNotFound(err) {
		return false
	}

	// SMTP ใช้ที่อยู่ของโดเมนได้เมื่อไม่มี MX จึงต้องตรวจ A และ AAAA ด้วย
	hosts, err := c.resolver.LookupHost(ctx, fqdn)
	return isNotFound(err) || (err == nil && len(hosts) == 0)
}

func isNotFound(err error) bool {
	var dnsErr *net.DNSError
	return errors.As(err, &dnsErr) && dnsErr.IsNotFound
}
