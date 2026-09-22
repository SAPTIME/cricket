COMPOSE      ?= docker compose
APP_SERVICE  ?= app
DB_SERVICE   ?= db

.PHONY: help up down logs shell migrate test build restart ps

help:
@echo "Доступные команды:"
@echo "  make up        — поднять все сервисы"
@echo "  make down      — остановить и удалить контейнеры"
@echo "  make logs      — логи всех сервисов (follow)"
@echo "  make shell     — shell внутри app-контейнера"
@echo "  make migrate   — применить миграции Alembic"
@echo "  make test      — запустить pytest"
@echo "  make build     — пересобрать образы"
@echo "  make restart   — перезапустить сервисы"
@echo "  make ps        — статус сервисов"

up:
$(COMPOSE) up -d --build

down:
$(COMPOSE) down

logs:
$(COMPOSE) logs -f --tail=200

shell:
$(COMPOSE) exec $(APP_SERVICE) /bin/bash

migrate:
$(COMPOSE) exec $(APP_SERVICE) alembic upgrade head

test:
$(COMPOSE) exec $(APP_SERVICE) pytest -q

build:
$(COMPOSE) build --no-cache

restart:
$(COMPOSE) restart

ps:
$(COMPOSE) ps
