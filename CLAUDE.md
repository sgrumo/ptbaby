# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Averziano is a Phoenix 1.8 application (JSON API + LiveView) built on the Ash framework (Ash 3 + AshPostgres + AshPhoenix) with PostgreSQL. Uses Bandit as HTTP server, binary UUIDs as primary keys, and esbuild/Tailwind for asset bundling.

## Common Commands

- `mix setup` — install deps, create DB, run migrations, seed, install assets
- `mix phx.server` — start the server (localhost:4000)
- `iex -S mix phx.server` — start with interactive shell
- `mix test` — run all tests (auto-creates/migrates DB via `ash.setup`)
- `mix test test/path/to/test.exs` — run a single test file
- `mix test test/path/to/test.exs:42` — run a specific test by line number
- `mix test --failed` — re-run previously failed tests
- `mix precommit` — compile (warnings-as-errors), unlock unused deps, format, `ash.codegen --check`, test. **Run before committing.**
- `mix ash.codegen <name>` — generate migrations + resource snapshots from resource changes (**never write migrations by hand**; `mix ash.codegen --dev` for throwaway dev iterations, then squash with a named run)
- `mix ash.codegen --check` — fail if resources have changes without a migration
- `mix ash.migrate` / `mix ash.reset` — run migrations / drop + recreate
- `mix ash.gen.domain Averziano.Name` / `mix ash.gen.resource Averziano.Name.Thing --domain Averziano.Name ...` — Igniter generators for new domains/resources
- `mix credo --strict` — static analysis
- `mix dialyzer` — type checking (first run builds PLT, takes a while)
- `make up` / `make down` — start/stop Docker Postgres
- `make dev-api` — start infra + setup + dev server

## Architecture

### Ash Domains (replaces Phoenix contexts)

Strict separation: `lib/averziano/` (Ash domains + resources) vs `lib/averziano_web/` (web layer).

- One domain per bounded context: `lib/averziano/accounts.ex` (`Averziano.Accounts`, `use Ash.Domain`) with resources under `lib/averziano/accounts/*.ex`.
- Every domain is registered in `config :averziano, ash_domains: [...]`.
- The domain's `code_interface` (`define :register_user, action: :register`) **is** the public API. The web layer calls `Accounts.register_user(params, actor: actor)` — never `Ash.create/read` on a resource, never `Repo`.
- Resources use `AshPostgres.DataLayer`, `Ash.Policy.Authorizer`, `uuid_primary_key :id`, and `timestamps()`. Prefer named, explicit actions with `accept` lists over wide defaults.
- Cross-cutting DSL config lives in `config/config.exs` (`config :ash, ...` backwards-compatibility flags, `config :spark, formatter: [section_order: ...]`).

### Error Flow

Domain calls return Ash errors (`Ash.Error.Invalid`, `Ash.Error.Forbidden`, ...). `Averziano.Errors.normalize/1` maps them to the typed tuples (`{:error, :not_found}`, `{:error, :forbidden}`, `{:error, :unprocessable_entity, %{field => [msg]}}`, `{:error, :internal_server_error}`); already-typed tuples pass through. The `FallbackController` accepts both raw Ash errors and typed tuples, so controllers use `action_fallback` and return whatever the domain returns. Validation errors render as `%{errors: %{field: [messages]}}`.

### Auth & Actors

Swappable token verification via config: `config :averziano, token_verifier: Averziano.Auth.Token` (production) / `Averziano.Auth.TokenMock` (test). `AverzianoWeb.Plugs.Auth` verifies the Bearer token, assigns `current_user_claims`, and sets the claims map as the Ash actor (`Ash.PlugHelpers.set_actor/2`; read with `Ash.PlugHelpers.get_actor/1`). LiveView auth uses the session-based `on_mount` hook (`AverzianoWeb.Live.AuthHook`), which assigns `:current_user_id` and `:actor`. Always pass `actor:` to domain calls; policies default to `authorize_if actor_present()`. Note: with `no_filter_static_forbidden_reads?: false`, a forbidden *read* returns an empty result instead of an error — writes raise `Ash.Error.Forbidden`.

### Router Organization

Pipelines: `:api`, `:browser`, `:authenticated`. Health check forwarded to `AverzianoWeb.Health.Router`. Scopes: public API, authenticated API, admin (browser + LiveView with auth hook).

### Web Module Dispatch

`AverzianoWeb` defines `:controller` (JSON-only) and `:html_controller` (HTML+JSON) quoted blocks, plus `:live_view`, `:live_component`, `:html`.

### OTP Supervision

Flat `one_for_one`: Telemetry -> Repo -> [TelemetryUI] -> DNSCluster -> PubSub -> Registry -> DynamicSupervisor -> Endpoint. Registry + DynamicSupervisor for per-session GenServer processes.

## Key Conventions

- Generators use `binary_id: true` and `utc_datetime` timestamps
- Use `Req` for HTTP requests (avoid HTTPoison, Tesla, httpc)
- Never nest multiple modules in the same file
- Attributes set programmatically (e.g. `user_id`) must not appear in an action's `accept` — set them via `change set_attribute/2`, `relate_actor/1`, or `manage_relationship`
- Use `Ash.Changeset.get_attribute/2` / `get_argument/2` to read changeset values in changes and validations
- Prefer `Ash.Query` (`require Ash.Query`, `Ash.Query.filter/2`) and calculations/aggregates over raw `Ecto.Query`
- Commit `priv/resource_snapshots/` together with the migrations `mix ash.codegen` generates
- Phoenix router `scope` blocks auto-prefix module aliases — don't duplicate them
- Use `start_supervised!/1` in tests; avoid `Process.sleep/1`
- Predicate functions end with `?` (no `is_` prefix unless it's a guard)
- Don't use `String.to_atom/1` on user input
- Every public function must have `@spec` (Credo strict mode enforces this)
- No vague module names: Manager, Helper, Utils, Fetcher, Builder, Serializer
- JSON API responses wrapped: `%{data: ...}`
- Test data via `Ash.Generator` (`test/support/generator.ex`, `Averziano.Generator`), auto-imported in ConnCase/DataCase: `generate(user(name: "Ada"))`, `generate_many(user(), 3)`. Generators run the real actions with `authorize?: false`.
- `actor()` in DataCase returns the test actor; `authenticate(conn)` in ConnCase adds the matching Bearer token

## Testing Principles

- Test observable behavior, not implementation details
- Avoid overlapping tests and subtle duplication
- Ensure every test actually runs (no dead conditional paths)
- Keep tests simple and fast
