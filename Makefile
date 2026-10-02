.PHONY: up down dev-api test

up:
	docker compose up -d

down:
	docker compose down

dev-api: up
	mix setup
	mix phx.server

test: up
	mix test

checklist:
	mix format --check-formatted
	mix credo --strict
	mix compile --warnings-as-errors
	mix ash.codegen --check
	mix test
