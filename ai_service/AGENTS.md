# AI Service Agent Guide

## Scope

These instructions apply to everything under `ai_service/`.

## Architecture

- Keep `main.py` limited to FastAPI lifecycle, schemas, middleware, and endpoint wiring.
- Keep environment parsing and defaults in `config.py` through Pydantic Settings.
- `app/agent/executor.py` orchestrates routing, tool execution, grounding, and response assembly.
- `app/llm/` owns Ollama communication; `app/tools/` owns Supabase inventory and external specification lookups.
- Reuse the shared `httpx.AsyncClient` lifecycle. Close clients during FastAPI shutdown and avoid blocking work on the event loop.
- Preserve the `POST /api/ai/chat` contract with the Go backend. Coordinate changes to request fields, response fields, status values, or timeouts with the backend adapter and documentation.

## Agent and data rules

- Treat current inventory, rental price, and availability as Supabase-backed facts. The model must use the inventory tool before making those claims.
- Use the web specification tool only for external product specifications or capabilities, not for Yuemnoi inventory or rental pricing.
- Keep tool inputs typed and validated with Pydantic. Never execute model-generated SQL or accept arbitrary query fragments.
- Preserve bounded input, history, search results, tool calls, and reference context to control latency and model context size.
- Preserve the response envelope: `status`, `search_status`, `items_found`, `answer`, and `recommended_items`, unless all consumers are updated together.
- Do not expose prompts, internal tool names, raw provider errors, chain-of-thought, or credentials in user-facing responses.
- When changing prompts or routing, test Thai and English requests covering direct conversation, inventory search, no inventory results, specification lookup, and upstream failure.

## Security and configuration

- Never commit, print, or embed values from `.env`.
- Treat `SUPABASE_KEY` and `SERPER_API_KEY` as secrets. Do not include them in logs, exceptions, fixtures, or example output.
- Configuration is loaded by `config.py` from process environment and `ai_service/.env`. Do not add fallback secrets.
- Do not make tests depend on live Supabase, Serper, or Ollama; mock HTTP boundaries instead.

## Python conventions

- Follow the existing async FastAPI, HTTPX, Pydantic, and type-hinting style.
- Catch errors at external-service boundaries and return stable application-level statuses.
- Keep dependencies pinned in `requirements.txt`; change it only when a dependency is necessary.
- Add focused tests for changed routing, validation, response shaping, or tool behavior. If introducing a test runner, do so only when the task explicitly requires it.

## Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Create all new test files inside the `tests/` directory.

No formatter, linter, or test runner is currently declared in the repository. Do not invent commands or add tooling just for verification. Report checks that could not run.
