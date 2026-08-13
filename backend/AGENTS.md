# Backend Agent Guide

## Scope

These instructions apply to everything under `backend/`.

## Architecture

- Keep the existing Hexagonal Architecture boundaries:
  - `cmd/server/` composes dependencies and starts the HTTP server.
  - `internal/domain/` contains business entities and ports; it must not depend on Gin, Supabase, or other infrastructure.
  - `internal/adapters/` implements domain ports for Supabase and external services.
  - `internal/ports/` owns Gin handlers, request/response mapping, middleware, and route registration.
- Add dependencies through interfaces in `internal/domain/` and inject implementations from `cmd/server/main.go`.
- Keep HTTP routes under `/api/v1` and register them in `internal/ports/router.go`. The health check remains `GET /health`.
- When an API contract changes, inspect and update every affected handler, domain interface, adapter, test, frontend caller, and README entry.

## Security and configuration

- Never commit or print secrets, access tokens, authorization headers, or user data.
- `SUPABASE_SERVICE_ROLE_KEY` is backend-only. Never expose it through an API response or copy it into frontend code.
- The server reads configuration with `os.Getenv`; it does not load `.env` automatically. Set variables in the process environment before running it.
- Required Supabase configuration is `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Defaults are port `8080` and `AI_SERVICE_URL=http://localhost:8000`.
- Derive authenticated user identity from the verified bearer token, never from a user ID supplied in a request body.
- Preserve context propagation and existing timeout behavior for database and external-service calls.

## Go conventions

- Make the smallest change that preserves the current package boundaries and constructor-based dependency injection.
- Return errors with useful context while avoiding secret or internal-detail leakage in client responses.
- Use standard-library facilities where practical and do not add dependencies unless the task requires them.
- Add focused table-driven or `httptest` tests. Do not require live Supabase or AI services in unit tests.
- Do not edit `go.mod` or `go.sum` unless dependencies actually change.

## Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Create all new test files inside the `tests/` directory.
