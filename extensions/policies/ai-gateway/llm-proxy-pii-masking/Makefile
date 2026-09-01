COMPOSE = docker compose -f gateway/dist/docker-compose.yaml -f docker-compose.yaml --project-directory gateway/dist

up:
	$(COMPOSE) up -d

setup:
	./scripts/setup.sh

down:
	$(COMPOSE) down

# Just the PII flow: raw in, masked out, masked back, restored out
logs:
	$(COMPOSE) logs -f --no-log-prefix gateway-runtime | grep --line-buffered -E "RECEIVED FROM CLIENT|SENT TO OPENAI|RECEIVED FROM OPENAI|RETURNED TO CLIENT"

runtime-logs:
	$(COMPOSE) logs -f gateway-runtime

gateway-logs:
	$(COMPOSE) logs -f gateway-controller

lint:
	uv run ruff check .

fmt:
	uv run ruff format .
