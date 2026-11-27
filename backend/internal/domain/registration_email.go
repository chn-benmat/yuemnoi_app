package domain

import (
	"context"
	"errors"
	"strings"
)

var ErrRegistrationEmailDomainUndeliverable = errors.New("registration email domain cannot receive mail")

type EmailDomainChecker interface {
	IsUndeliverable(ctx context.Context, name string) bool
}

type emailCheckedAuthGateway struct {
	AuthGateway
	checker EmailDomainChecker
}

func WithRegistrationEmailCheck(gateway AuthGateway, checker EmailDomainChecker) AuthGateway {
	return emailCheckedAuthGateway{AuthGateway: gateway, checker: checker}
}

func (g emailCheckedAuthGateway) Register(ctx context.Context, user RegisterUser) (*RegisterResult, error) {
	separator := strings.LastIndexByte(user.Email, '@')
	if separator >= 0 && g.checker.IsUndeliverable(ctx, user.Email[separator+1:]) {
		return nil, ErrRegistrationEmailDomainUndeliverable
	}
	return g.AuthGateway.Register(ctx, user)
}
