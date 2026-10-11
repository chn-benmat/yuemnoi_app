# Backend Agent Guide

## Scope

These instructions apply to everything under `backend/`.

## Architecture

- Keep the existing Hexagonal Architecture boundaries:
  - Root `main.go` is the server entrypoint: it composes dependencies and starts the Fiber HTTP server through `Listen`. Run it directly from `backend/` with `go run main.go`.
  - `internal/config/` manages centralized type-safe configuration (`caarlos0/env/v11`, `godotenv`).
  - `internal/domain/` contains business entities and ports; it must not depend on Fiber, Supabase, or other infrastructure.
  - `internal/adapters/` implements domain ports for Supabase and external services.
  - `internal/ports/` owns Fiber handlers, request/response mapping, middleware, and route registration.
- Add dependencies through interfaces in `internal/domain/` and inject implementations from root `main.go`.
- Keep HTTP routes under `/api` and register them in `internal/ports/router.go`. The health check remains `GET /health`.
- When an API contract changes, inspect and update every affected handler, domain interface, adapter, test, frontend caller, and README entry.

## Fiber transport

- Use native Fiber v3 handlers and middleware in `internal/ports/`. Keep outbound service calls in adapters.
- Create apps through `ports.NewHTTPApp` or `ports.SetupRouter` so production and tests share validation, body limits, error mapping, and request lifecycle behavior.
- Use `validate` tags on request DTOs. Check required text after trimming whitespace, and preserve omitted versus explicitly empty values in partial updates.
- Keep `fiber.Ctx` within the handler lifetime. Copy request values needed by background jobs; pass `context.Context` through domain ports and adapters. SSE callbacks own upstream body closure and cancellation.
- Before changing binding, uploads, SSE, timeouts, or shutdown, read [API test report](tests/API_TEST_REPORT.md) for regression coverage and known transport limitations. Recheck its dated findings against current code and tests.

## Security and configuration

- Never commit or print secrets, access tokens, authorization headers, or user data.
- `SUPABASE_SERVICE_ROLE_KEY` is backend-only. Never expose it through an API response or copy it into frontend code.
- Configuration must be defined in `internal/config/config.go` using `github.com/caarlos0/env/v11`. `.env` is loaded automatically if present. Do not use direct `os.Getenv` calls outside the config package.
- Required Supabase configuration is `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Default port is `8080`.
- Derive authenticated user identity from the verified bearer token, never from a user ID supplied in a request body.
- Preserve context propagation and existing timeout behavior for database and external-service calls.
- Use `log/slog` for structured logging, and ensure sensitive data (passwords, tokens, OTPs, PII) are redacted in audit logs.

## Go conventions

- Make the smallest change that preserves the current package boundaries and constructor-based dependency injection.
- Return errors with useful context while avoiding secret or internal-detail leakage in client responses.
- Use standard-library facilities where practical and do not add dependencies unless the task requires them.
- Add focused table-driven HTTP contract tests with Fiber `app.Test` (and real loopback sockets for streaming/lifecycle behavior) using `github.com/stretchr/testify` (`assert`/`require`). Do not require live Supabase services in unit tests.
- Do not edit `go.mod` or `go.sum` unless dependencies actually change.

## Verification

- When adding or removing routes, update the endpoint contract matrix in `tests/api_contract_test.go`; it must match the registered routes.
- After changing Go code or merging upstream changes, run `go test ./...`, `go vet ./...`, and `go build ./...` from `backend/`.
- Report checks run, failures, skipped tests, and remaining limitations. Distinguish tests against local fake services from live end-to-end verification.

## Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Create all new test files inside the `tests/` directory.
