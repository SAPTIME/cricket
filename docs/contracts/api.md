# API-контракты «Сверчок» (MVP)

> Документ: `/docs/contracts/api.md`
> Версия: 1.1
> База: `/api/v1`
> Формат: JSON, UTF-8
> Аутентификация: серверная сессия через HttpOnly cookie + CSRF-заголовок

---

## 0. Общие правила

### 0.1. Версионирование

Все эндпоинты имеют префикс `/api/v1/...`. Админка — `/admin-{random}/...` (random задаётся переменной окружения `ADMIN_PATH_PREFIX`).

### 0.2. Формат ID

Все ID — UUID v4 в нижнем регистре: `"9c3f2a1e-7b4d-4e8f-a1c2-3d5e6f7a8b9c"`.

### 0.3. Формат дат

ISO 8601 с таймзоной: `"2025-01-15T10:30:00+03:00"`. Даты без времени — `"2025-01-15"`.

### 0.4. Единый формат ошибок

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Поле email обязательно",
  "details": {
    "field": "email",
    "reason": "required"
  }
}
```

| HTTP | code | Когда |
|---|---|---|
| 400 | `BAD_REQUEST` | Некорректный запрос (битый JSON, отсутствует параметр) |
| 401 | `UNAUTHORIZED` | Нет сессии / сессия истекла |
| 403 | `FORBIDDEN` | Нет прав (чужой ресурс, не админ) |
| 403 | `CSRF_INVALID` | Отсутствует/неверный `X-CSRF-Token` |
| 404 | `NOT_FOUND` | Ресурс не найден |
| 409 | `CONFLICT` | Дубликат (email, title колоды) |
| 422 | `VALIDATION_ERROR` | Ошибка валидации Pydantic |
| 429 | `RATE_LIMITED` | Превышен лимит; заголовок `Retry-After` |
| 500 | `INTERNAL_ERROR` | Внутренняя ошибка |

### 0.5. CSRF

- После `login` сервер выдаёт cookie `csrf_token` (не HttpOnly) и заголовок `X-CSRF-Token`.
- Все **мутирующие** запросы (`POST`, `PATCH`, `PUT`, `DELETE`) требуют заголовок `X-CSRF-Token: <token>`.
- При несовпадении — `403 CSRF_INVALID`.

### 0.6. Cookie сессии

| Параметр | Значение |
|---|---|
| Имя | `sv_session` |
| HttpOnly | да |
| Secure | да (в prod) |
| SameSite | `Lax` |
| Path | `/` |
| Max-Age | 30 дней (скользящая) |
| Домен | текущий |

CSRF-cookie: `csrf_token`, HttpOnly=**нет**, Secure=да, SameSite=Lax, Max-Age=30 дней.

### 0.7. Пагинация

Query-параметры:
- `limit` — integer, 1..100, по умолчанию `20`.
- `offset` — integer, ≥ 0, по умолчанию `0`.

Ответ со списком:
```json
{
  "items": [ /* ... */ ],
  "total": 123,
  "limit": 20,
  "offset": 0
}
```

### 0.8. Фильтрация и сортировка

- Фильтры — query-параметры (`status`, `bucket`, `deck_id`, `language_group_id`).
- Сортировка: `sort=field` и `order=asc|desc`. Допустимые поля — в каждом endpoint.

### 0.9. Rate-limit

| Endpoint | Лимит |
|---|---|
| `POST /auth/login` | 5 / 15 мин / IP+email |
| `POST /auth/register` | 3 / час / IP |
| `POST /auth/forgot-password` | 3 / час / IP |
| `POST /auth/resend-code` | 3 / час / user |
| Остальной API | 100 / мин / user (или IP) |
| Admin | 60 / мин / admin |

При превышении — `429 RATE_LIMITED`, заголовок `Retry-After: <seconds>`.

### 0.10. Аутентификация — типы

- **cookie** — требуется валидная сессия (`sv_session`).
- **csrf** — требуется заголовок `X-CSRF-Token` (только мутирующие).
- **admin** — требуется admin-сессия + TOTP + CSRF.
- **public** — без аутентификации.

### 0.11. Что попадает в `events`

В `events` пишутся **только значимые события жизненного цикла** сущностей и сессий. Операционные события обучения (просмотр, переворот, свайп, отмена) в `events` **не дублируются** — они фиксируются в `card_session_history` и агрегируются в `card_stats` / `user_daily_stats` / `bucket_stats`.

**Пишутся в `events`:**
`auth.register`, `auth.email_verified`, `auth.code_resent`, `auth.login_success`, `auth.login_failed`, `auth.logout`, `auth.password_reset_requested`, `auth.password_reset`, `auth.password_changed`, `user.profile_updated`, `user.avatar_updated`, `user.deleted`, `language_group.created`, `language_group.deleted`, `deck.created`, `deck.updated`, `deck.deleted`, `deck.shuffled`, `card.created`, `card.updated`, `card.deleted`, `card.bucket_changed`, `card.status_changed`, `session.started`, `session.ended`, admin-события.

**НЕ пишутся в `events`:**
`card.viewed`, `card.flipped`, `card.swiped`, `card.swipe_reverted`.

---

## 1. Auth

### 1.1. `POST /api/v1/auth/register`

**Назначение:** регистрация нового пользователя.
**Аутентификация:** public.
**Rate-limit:** 3/час/IP.

**Request body:**
```json
{
  "email": "string (email, обязательный)",
  "password": "string (8..128, обязательный)",
  "display_name": "string (0..100, опционально)",
  "timezone": "string (IANA, опционально, default 'UTC')",
  "locale": "string (опционально, default 'ru')"
}
```

**Response 201:**
```json
{
  "user_id": "uuid",
  "email": "string",
  "email_verified": false,
  "message": "Код подтверждения отправлен на email"
}
```

**Ошибки:** 400, 409 (`EMAIL_TAKEN`), 422, 429.

**Побочные эффекты:**
- INSERT `users` (password_hash — argon2id, email_verified_at = NULL).
- INSERT `email_verifications` (purpose=`email_verify`, TTL 15 мин).
- INSERT `events`: `auth.register`.
- Отправка письма с 6-значным кодом.

---

### 1.2. `POST /api/v1/auth/verify-email`

**Назначение:** подтверждение email 6-значным кодом.
**Аутентификация:** public.

**Request body:**
```json
{
  "email": "string (email)",
  "code": "string (6 цифр)"
}
```

**Response 200:**
```json
{
  "user_id": "uuid",
  "email_verified": true,
  "session": {
    "expires_at": "ISO8601"
  }
}
```

**Ошибки:** 400 (`CODE_INVALID`), 404, 410 (`CODE_EXPIRED`), 422, 429.

**Побочные эффекты:**
- UPDATE `users.email_verified_at = now()`.
- UPDATE `email_verifications.used_at = now()`.
- INSERT `events`: `auth.email_verified`.
- Установка cookie `sv_session` + `csrf_token`.

---

### 1.3. `POST /api/v1/auth/resend-code`

**Назначение:** повторная отправка кода подтверждения.
**Аутентификация:** public.
**Rate-limit:** 3/час/user.

**Request body:**
```json
{ "email": "string (email)" }
```

**Response 200:**
```json
{ "message": "Код отправлен повторно", "expires_at": "ISO8601" }
```

**Ошибки:** 404, 429.

**Побочные эффекты:**
- INSERT `email_verifications` (новый код; старые неиспользованные инвалидируются).
- INSERT `events`: `auth.code_resent`.

---

### 1.4. `POST /api/v1/auth/login`

**Назначение:** вход по email и паролю.
**Аутентификация:** public.
**Rate-limit:** 5/15 мин/IP+email.

**Request body:**
```json
{
  "email": "string (email)",
  "password": "string",
  "remember": "boolean (опционально, default false)"
}
```

**Response 200:**
```json
{
  "user": {
    "id": "uuid",
    "email": "string",
    "display_name": "string|null",
    "avatar_url": "string|null",
    "email_verified": true,
    "timezone": "string",
    "locale": "string",
    "theme": "light|dark|system"
  },
  "csrf_token": "string"
}
```

Устанавливает cookies `sv_session` и `csrf_token`.

**Ошибки:** 400, 401 (`INVALID_CREDENTIALS`), 403 (`EMAIL_NOT_VERIFIED`), 423 (`ACCOUNT_LOCKED`), 429.

**Побочные эффекты:**
- INSERT `login_history` (success true/false).
- При успехе: UPDATE `users.last_login_at`, `failed_login_count = 0`, `locked_until = NULL`.
- При неудаче: `failed_login_count += 1`; при ≥ 5 — `locked_until = now() + 15 min`.
- INSERT `events`: `auth.login_success` / `auth.login_failed`.

---

### 1.5. `POST /api/v1/auth/logout`

**Назначение:** выход, инвалидация сессии.
**Аутентификация:** cookie + csrf.

**Response 200:** `{ "message": "Вы вышли" }`
Удаляет cookies `sv_session`, `csrf_token`.

**Ошибки:** 401, 403.

**Побочные эффекты:** INSERT `events`: `auth.logout`.

---

### 1.6. `POST /api/v1/auth/forgot-password`

**Назначение:** запрос кода сброса пароля.
**Аутентификация:** public.
**Rate-limit:** 3/час/IP.

**Request body:** `{ "email": "string (email)" }`

**Response 200:** `{ "message": "Если email существует, код отправлен" }` (не раскрываем существование email).

**Ошибки:** 422, 429.

**Побочные эффекты:**
- Если пользователь есть: INSERT `email_verifications` (purpose=`password_reset`, TTL 15 мин).
- INSERT `events`: `auth.password_reset_requested`.

---

### 1.7. `POST /api/v1/auth/reset-password`

**Назначение:** сброс пароля по коду.
**Аутентификация:** public.

**Request body:**
```json
{
  "email": "string (email)",
  "code": "string (6 цифр)",
  "new_password": "string (8..128)"
}
```

**Response 200:** `{ "message": "Пароль изменён" }`

**Ошибки:** 400 (`CODE_INVALID`), 404, 410 (`CODE_EXPIRED`), 422, 429.

**Побочные эффекты:**
- UPDATE `users.password_hash`.
- UPDATE `email_verifications.used_at`.
- Инвалидация всех активных сессий пользователя.
- INSERT `events`: `auth.password_reset`.

---

### 1.8. `POST /api/v1/auth/change-password`

**Назначение:** смена пароля авторизованным пользователем.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "current_password": "string",
  "new_password": "string (8..128)"
}
```

**Response 200:** `{ "message": "Пароль изменён" }`

**Ошибки:** 400, 401, 403, 422.

**Побочные эффекты:**
- UPDATE `users.password_hash`.
- Инвалидация всех сессий, кроме текущей.
- INSERT `events`: `auth.password_changed`.

---

## 2. Profile

### 2.1. `GET /api/v1/me`

**Назначение:** получить профиль текущего пользователя.
**Аутентификация:** cookie.

**Response 200:**
```json
{
  "id": "uuid",
  "email": "string",
  "display_name": "string|null",
  "avatar_url": "string|null",
  "email_verified": true,
  "timezone": "string",
  "locale": "string",
  "theme": "light|dark|system",
  "created_at": "ISO8601",
  "stats": {
    "language_groups": 3,
    "decks": 12,
    "cards": 480,
    "cards_mastered": 130,
    "streak_days": 7
  }
}
```

**Ошибки:** 401.

---

### 2.2. `PATCH /api/v1/me`

**Назначение:** обновить профиль.
**Аутентификация:** cookie + csrf.

**Request body (все поля опциональны):**
```json
{
  "display_name": "string|null",
  "timezone": "string (IANA)",
  "locale": "string",
  "theme": "light|dark|system"
}
```

**Response 200:** профиль (как в 2.1).

**Ошибки:** 401, 403, 422.

**Побочные эффекты:** UPDATE `users`; INSERT `events`: `user.profile_updated`.

---

### 2.3. `POST /api/v1/me/avatar`

**Назначение:** загрузить аватар.
**Аутентификация:** cookie + csrf.
**Content-Type:** `multipart/form-data`.

**Request:** `file` — image (jpeg/png/webp, ≤ 2 МБ).

**Response 200:** `{ "avatar_url": "string" }`

**Ошибки:** 400 (`INVALID_IMAGE`), 401, 403, 413 (`FILE_TOO_LARGE`), 422.

**Побочные эффекты:** UPDATE `users.avatar_url`; INSERT `events`: `user.avatar_updated`.

---

### 2.4. `DELETE /api/v1/me`

**Назначение:** soft-delete аккаунта (GDPR).
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{ "password": "string", "confirm": "DELETE" }
```

**Response 200:** `{ "message": "Аккаунт удалён", "purge_after": "ISO8601" }`

**Ошибки:** 400, 401, 403, 422.

**Побочные эффекты:**
- UPDATE `users.deleted_at = now()`.
- INSERT `deleted_users` (payload = JSON-дамп, purge_after = +30 дней).
- Инвалидация всех сессий.
- INSERT `events`: `user.deleted`.

---

### 2.5. `GET /api/v1/me/stats`

**Назначение:** дневная статистика пользователя за период.
**Аутентификация:** cookie.

**Query:**
- `from` (date, optional) — по умолчанию −30 дней.
- `to` (date, optional) — по умолчанию сегодня.
- `limit`, `offset`.

**Response 200:**
```json
{
  "items": [
    {
      "day": "2025-01-15",
      "cards_viewed": 42,
      "cards_swiped_left": 10,
      "cards_swiped_right": 32,
      "sessions_count": 3,
      "time_total_ms": 540000,
      "cards_mastered": 5
    }
  ],
  "total": 30, "limit": 30, "offset": 0,
  "summary": {
    "streak_days": 7,
    "cards_viewed": 520,
    "time_total_ms": 7200000,
    "cards_mastered": 45
  }
}
```

**Ошибки:** 401, 422.

---

## 3. Languages

### 3.1. `GET /api/v1/languages`

**Назначение:** справочник языков ISO 639-1.
**Аутентификация:** public.

**Query:** `q` (trgm-поиск по name_ru/name_en), `limit`, `offset`.

**Response 200:**
```json
{
  "items": [
    {
      "code": "en",
      "code_alpha3": "eng",
      "name_ru": "Английский",
      "name_en": "English",
      "native_name": "English"
    }
  ],
  "total": 184, "limit": 20, "offset": 0
}
```

**Ошибки:** 422.

---

### 3.2. `GET /api/v1/language-groups`

**Назначение:** список групп языков пользователя.
**Аутентификация:** cookie.

**Query:** `limit`, `offset`.

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "language_code": "en",
      "language": {
        "code": "en", "name_ru": "Английский", "name_en": "English"
      },
      "title": "string|null",
      "decks_count": 4,
      "cards_count": 120,
      "created_at": "ISO8601"
    }
  ],
  "total": 3, "limit": 20, "offset": 0
}
```

**Ошибки:** 401.

---

### 3.3. `POST /api/v1/language-groups`

**Назначение:** создать группу языков.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "language_code": "string (2 буквы, ISO 639-1)",
  "title": "string|null (0..100)"
}
```

**Response 201:** объект группы (как в 3.2).

**Ошибки:** 400 (`LANGUAGE_NOT_FOUND`), 401, 403, 409 (`GROUP_EXISTS`), 422.

**Побочные эффекты:** INSERT `language_groups`; INSERT `events`: `language_group.created`.

---

### 3.4. `DELETE /api/v1/language-groups/:id`

**Назначение:** удалить группу языков со всеми колодами.
**Аутентификация:** cookie + csrf.

**Response 200:** `{ "message": "Группа удалена", "deleted_decks": 4, "deleted_cards": 120 }`

**Ошибки:** 401, 403 (`NOT_OWNER`), 404.

**Побочные эффекты:**
- Soft-delete `decks` и `cards` группы.
- INSERT `events`: `language_group.deleted`.

---

## 4. Decks

### 4.1. `GET /api/v1/decks`

**Назначение:** список колод пользователя.
**Аутентификация:** cookie.

**Query:** `language_group_id` (uuid, optional), `is_archived` (bool, default false), `sort` (`created_at|title|cards_count`), `order`, `limit`, `offset`.

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "language_group_id": "uuid",
      "title": "string",
      "description": "string|null",
      "source_lang": "en",
      "target_lang": "ru",
      "position": 1,
      "cards_count": 40,
      "is_archived": false,
      "buckets": { "1": 10, "2": 8, "3": 6, "4": 6, "5": 5, "6": 5 },
      "created_at": "ISO8601",
      "updated_at": "ISO8601"
    }
  ],
  "total": 12, "limit": 20, "offset": 0
}
```

**Ошибки:** 401.

---

### 4.2. `POST /api/v1/decks`

**Назначение:** создать колоду.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "language_group_id": "uuid",
  "title": "string (1..200)",
  "description": "string|null (0..2000)",
  "source_lang": "string (2 буквы)",
  "target_lang": "string (2 буквы)",
  "position": "integer (опционально)"
}
```

**Response 201:** объект колоды (как в 4.1).

**Ошибки:** 400 (`LANGS_EQUAL`), 401, 403, 404 (`GROUP_NOT_FOUND`), 409 (`TITLE_EXISTS`), 422.

**Побочные эффекты:** INSERT `decks`; INSERT `deck_bucket_progress` (6 строк со счётчиком 0); INSERT `events`: `deck.created`.

---

### 4.3. `GET /api/v1/decks/:id`

**Назначение:** получить колоду.
**Аутентификация:** cookie.

**Response 200:** объект колоды + `caret_position`.

**Ошибки:** 401, 403, 404.

---

### 4.4. `PATCH /api/v1/decks/:id`

**Назначение:** обновить колоду.
**Аутентификация:** cookie + csrf.

**Request body (опционально):**
```json
{
  "title": "string",
  "description": "string|null",
  "position": "integer",
  "caret_position": "integer",
  "is_archived": "boolean"
}
```

**Response 200:** объект колоды.

**Ошибки:** 401, 403, 404, 409, 422.

**Побочные эффекты:** UPDATE `decks`; INSERT `events`: `deck.updated`.

---

### 4.5. `DELETE /api/v1/decks/:id`

**Назначение:** soft-delete колоды.
**Аутентификация:** cookie + csrf.

**Response 200:** `{ "message": "Колода удалена", "deleted_cards": 40 }`

**Ошибки:** 401, 403, 404.

**Побочные эффекты:**
- Soft-delete `decks` и всех `cards`.
- INSERT `deleted_cards` (для каждой карточки) + вычет из `card_stats`, `deck_bucket_progress`, `bucket_stats`, `user_daily_stats`.
- INSERT `events`: `deck.deleted`.

---

### 4.6. `POST /api/v1/decks/:id/shuffle`

**Назначение:** перемешать **всю** колоду. Каретка сбрасывается в 1.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "reset_positions": "boolean (default false)"
}
```

> Параметр `bucket` убран — перемешивается вся колода.

**Response 200:**
```json
{
  "message": "Перемешано",
  "shuffled_cards": 40,
  "caret_position": 1
}
```

**Ошибки:** 401, 403, 404, 422.

**Побочные эффекты:**
- UPDATE `cards.position` для всех карточек колоды (пересчёт порядка).
- UPDATE `decks.caret_position = 1`.
- INSERT `events`: `deck.shuffled`.

---

## 5. Cards

### 5.1. `GET /api/v1/decks/:id/cards`

**Назначение:** список карточек колоды.
**Аутентификация:** cookie.

**Query:** `status` (`new|learning|mastered`), `bucket` (1..6), `q` (trgm-поиск по front), `sort` (`position|created_at|bucket`), `order`, `limit`, `offset`.

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "deck_id": "uuid",
      "position": 1,
      "status": "new",
      "bucket": 1,
      "front": "hello",
      "translations": [{"lang":"ru","text":"привет"}],
      "transcriptions": [{"type":"ipa","text":"həˈloʊ"}],
      "examples": [{"source":"Hello!","target":"Привет!"}],
      "notes": "string|null",
      "stats": {
        "views_count": 5,
        "flips_count": 3,
        "swipes_left": 1,
        "swipes_right": 4,
        "time_total_ms": 12000,
        "edits_count": 0,
        "last_seen_at": "ISO8601"
      },
      "created_at": "ISO8601",
      "updated_at": "ISO8601"
    }
  ],
  "total": 40, "limit": 20, "offset": 0
}
```

**Примечание:** отдельный endpoint для архива mastered-карточек **не нужен**. Используется фильтр `?status=mastered`.

**Ошибки:** 401, 403, 404.

---

### 5.2. `POST /api/v1/decks/:id/cards`

**Назначение:** создать карточку.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "front": "string (1..500)",
  "translations": [{"lang":"ru","text":"string"}],
  "transcriptions": [{"type":"ipa|other","text":"string"}],
  "examples": [{"source":"string","target":"string"}],
  "notes": "string|null",
  "position": "integer (опционально, default = caret_position)"
}
```

**Response 201:** объект карточки.

**Ошибки:** 400, 401, 403, 404, 409 (`POSITION_TAKEN`), 422.

**Побочные эффекты:**
- INSERT `cards` (status='new', bucket=1).
- UPDATE `decks.cards_count += 1`, `caret_position += 1`.
- INSERT `card_stats` (нули).
- UPDATE `deck_bucket_progress` (bucket=1, +1).
- INSERT `bucket_stats` (inflow bucket=1 за сегодня).
- INSERT `events`: `card.created`.

---

### 5.3. `GET /api/v1/cards/:id`

**Назначение:** получить карточку.
**Аутентификация:** cookie.

**Response 200:** объект карточки + `stats` (из `card_stats`).

**Ошибки:** 401, 403, 404.

---

### 5.4. `PATCH /api/v1/cards/:id`

**Назначение:** обновить карточку.
**Аутентификация:** cookie + csrf.

**Request body (опционально):**
```json
{
  "front": "string (1..500)",
  "translations": [{"lang":"ru","text":"string"}],
  "transcriptions": [{"type":"ipa|other","text":"string"}],
  "examples": [{"source":"string","target":"string"}],
  "notes": "string|null",
  "position": "integer"
}
```

**Response 200:** объект карточки + поле `edits_count`.

**Ошибки:** 401, 403, 404, 409 (`POSITION_TAKEN`), 422.

**Побочные эффекты:**
- UPDATE `cards` (указанные поля).
- **UPDATE `card_stats.edits_count += 1`** (инкремент при каждом успешном PATCH).
- INSERT `events`: `card.updated`.

**Примечание:** поле `edits_count` живёт в `card_stats` (per card per user), т.к. правки — часть пользовательской статистики. Миграция:

```sql
ALTER TABLE card_stats
    ADD COLUMN edits_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN card_stats.edits_count IS
    'Сколько раз карточку редактировали через PATCH /cards/:id';
```

---

### 5.5. `DELETE /api/v1/cards/:id`

**Назначение:** soft-delete карточки.
**Аутентификация:** cookie + csrf.

**Response 200:** `{ "message": "Карточка удалена" }`

**Ошибки:** 401, 403, 404.

**Побочные эффекты:**
- UPDATE `cards.deleted_at = now()`.
- INSERT `deleted_cards` (payload + stats_snapshot).
- UPDATE `decks.cards_count -= 1`.
- UPDATE `deck_bucket_progress` (bucket карточки, −1).
- UPDATE `card_stats` (вычитание агрегатов).
- INSERT `events`: `card.deleted`.

---

### 5.6. `PATCH /api/v1/cards/:id/bucket`

**Назначение:** вручную переместить карточку в другую коробку. **Статус карточки не меняется** — коробка и статус независимы.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "bucket": "integer (1..6)",
  "reason": "string|null (опционально)"
}
```

**Response 200:**
```json
{
  "card_id": "uuid",
  "bucket": 3,
  "status": "learning"
}
```

> `status` возвращается как есть (не изменялся).

**Ошибки:** 400 (`INVALID_BUCKET`), 401, 403, 404, 422.

**Побочные эффекты:**
- UPDATE `cards.bucket` (только bucket; `cards.status` не трогаем).
- UPDATE `deck_bucket_progress` (outflow старой коробки, inflow новой).
- INSERT `bucket_stats` (outflow/inflow за сегодня).
- INSERT `events`: `card.bucket_changed`.
- `card_stats` не меняется.

---

### 5.7. `PATCH /api/v1/cards/:id/status`

**Назначение:** изменить статус карточки. **Единственный способ перевести карточку в `mastered`.**
**Аутентификация:** cookie + csrf.

**Request body:** `{ "status": "new|learning|mastered" }`

**Response 200:** `{ "card_id": "uuid", "status": "mastered" }`

**Ошибки:** 401, 403, 404, 422.

**Побочные эффекты:**
- UPDATE `cards.status`; при `mastered` — `card_stats.mastered_at = now()`.
- UPDATE `user_daily_stats.cards_mastered += 1` (если переход в mastered).
- INSERT `events`: `card.status_changed`.

---

### 5.8. `GET /api/v1/cards/:id/stats`

**Назначение:** полная статистика карточки.
**Аутентификация:** cookie.

**Response 200:**
```json
{
  "card_id": "uuid",
  "stats": {
    "views_count": 5,
    "flips_count": 3,
    "swipes_left": 1,
    "swipes_right": 4,
    "time_front_ms": 5000,
    "time_back_ms": 7000,
    "time_total_ms": 12000,
    "edits_count": 0,
    "sessions_count": 2,
    "first_seen_at": "ISO8601",
    "last_seen_at": "ISO8601",
    "last_swipe_at": "ISO8601",
    "last_swipe_dir": "right",
    "mastered_at": "ISO8601|null"
  },
  "history": [
    {
      "session_id": "uuid",
      "viewed_at": "ISO8601",
      "flipped": true,
      "time_front_ms": 2000,
      "time_back_ms": 3000,
      "swipe_dir": "right",
      "reverted": false
    }
  ]
}
```

**Ошибки:** 401, 403, 404.

---

## 6. Learning

### 6.1. `POST /api/v1/sessions/start`

**Назначение:** начать сессию обучения.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "deck_id": "uuid",
  "bucket": "integer (1..6, default 1)",
  "direction": "source_to_target|target_to_source (default source_to_target)",
  "shuffled": "boolean (default false)"
}
```

**Response 201:**
```json
{
  "session_id": "uuid",
  "deck_id": "uuid",
  "bucket": 1,
  "direction": "source_to_target",
  "cards_total": 10,
  "started_at": "ISO8601",
  "first_card": {
    "id": "uuid",
    "front": "hello",
    "translations": [{"lang":"ru","text":"привет"}],
    "transcriptions": [{"type":"ipa","text":"həˈloʊ"}],
    "examples": [{"source":"Hello!","target":"Привет!"}]
  }
}
```

**Ошибки:** 400 (`NO_CARDS_IN_BUCKET`), 401, 403, 404, 409 (`ACTIVE_SESSION_EXISTS`), 422.

**Побочные эффекты:**
- INSERT `learning_sessions` (cards_total = count карточек в bucket).
- INSERT `events`: `session.started`.
- UPDATE `user_daily_stats.sessions_count += 1`.

---

### 6.2. `GET /api/v1/sessions/:id/next`

**Назначение:** получить следующую карточку.
**Аутентификация:** cookie.

**Response 200:**
```json
{
  "card": {
    "id": "uuid", "front": "string", "translations": [], "transcriptions": [], "examples": []
  },
  "progress": {
    "cards_viewed": 4, "cards_total": 10,
    "cards_swiped_left": 1, "cards_swiped_right": 3
  },
  "finished": false
}
```

Если карточки закончились: `{ "card": null, "finished": true, "progress": {...} }`.

**Ошибки:** 401, 403, 404, 410 (`SESSION_ENDED`).

**Побочные эффекты:** INSERT `card_session_history` (viewed_at = now()).

---

### 6.3. `POST /api/v1/sessions/:id/view`

**Назначение:** зафиксировать просмотр карточки (фронт/бэк).
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "card_id": "uuid",
  "side": "front|back",
  "duration_ms": "integer (≥ 0)"
}
```

**Response 200:** `{ "ok": true }`

**Ошибки:** 401, 403, 404, 410, 422.

**Побочные эффекты:**
- UPDATE `card_session_history.time_front_ms|time_back_ms`.
- UPDATE `card_stats.time_front_ms|time_back_ms|time_total_ms`.
- UPDATE `learning_sessions.cards_viewed += 1`, `last_activity_at = now()`.
- UPDATE `user_daily_stats.cards_viewed += 1`, `time_total_ms += duration_ms`.
- `events` **не пишется**.

---

### 6.4. `POST /api/v1/sessions/:id/flip`

**Назначение:** переворот карточки.
**Аутентификация:** cookie + csrf.

**Request body:** `{ "card_id": "uuid" }`

**Response 200:** `{ "ok": true, "flips_count": 2 }`

**Ошибки:** 401, 403, 404, 410, 422.

**Побочные эффекты:**
- UPDATE `card_session_history.flipped = true`, `flips_count += 1`.
- UPDATE `card_stats.flips_count += 1`.
- `events` **не пишется**.

---

### 6.5. `POST /api/v1/sessions/:id/swipe`

**Назначение:** свайп карточки (влево/вправо) — ответ пользователя. **Переход в `mastered` здесь не происходит** — только вручную через `PATCH /cards/:id/status`.
**Аутентификация:** cookie + csrf.

**Request body:**
```json
{
  "card_id": "uuid",
  "direction": "left|right"
}
```

**Response 200:**
```json
{
  "card_id": "uuid",
  "direction": "right",
  "new_bucket": 2,
  "new_status": "learning"
}
```

**Ошибки:** 401, 403, 404, 409 (`ALREADY_SWIPED`), 410, 422.

**Побочные эффекты:**
- UPDATE `card_session_history.swipe_dir`, `swiped_at`.
- UPDATE `card_stats.swipes_left|swipes_right += 1`, `last_swipe_at`, `last_swipe_dir`.
- UPDATE `learning_sessions.cards_swiped_left|right += 1`, `last_activity_at`.
- UPDATE `user_daily_stats.cards_swiped_left|right += 1`.
- Логика Лейтнера (bucket only):
  - `right` → `bucket = min(bucket + 1, 6)`.
  - `left` → `bucket = 1`.
- `cards.status` **не меняется** этим endpoint'ом.
- UPDATE `cards.bucket`.
- UPDATE `deck_bucket_progress` (outflow старой, inflow новой).
- INSERT `bucket_stats` (outflow/inflow за сегодня).
- `events` **не пишется**.

> Переход в `mastered` — отдельным вызовом `PATCH /api/v1/cards/:id/status` с `{"status":"mastered"}`.

---

### 6.6. `POST /api/v1/sessions/:id/revert`

**Назначение:** отменить последний свайп.
**Аутентификация:** cookie + csrf.

**Request body:** `{ "card_id": "uuid" }`

**Response 200:**
```json
{
  "card_id": "uuid",
  "reverted_bucket": 1,
  "reverted_status": "learning"
}
```

**Ошибки:** 401, 403, 404, 409 (`NOTHING_TO_REVERT`), 410.

**Побочные эффекты:**
- UPDATE `card_session_history.reverted = true`, `reverted_at`.
- UPDATE `card_stats` (вычитание последнего свайпа).
- UPDATE `learning_sessions` (вычитание счётчика).
- UPDATE `user_daily_stats` (вычитание).
- UPDATE `cards.bucket` (возврат; `status` не трогаем).
- UPDATE `deck_bucket_progress` (обратный outflow/inflow).
- INSERT `bucket_stats` (обратные inflow/outflow).
- `events` **не пишется**.

---

### 6.7. `POST /api/v1/sessions/:id/end`

**Назначение:** завершить сессию.
**Аутентификация:** cookie + csrf.

**Request body:** `{ "reason": "manual|timeout (default manual)" }`

**Response 200:**
```json
{
  "session_id": "uuid",
  "ended_at": "ISO8601",
  "duration_seconds": 480,
  "summary": {
    "cards_viewed": 10,
    "cards_swiped_left": 3,
    "cards_swiped_right": 7,
    "time_total_ms": 480000
  }
}
```

**Ошибки:** 401, 403, 404, 409 (`ALREADY_ENDED`), 422.

**Побочные эффекты:**
- UPDATE `learning_sessions.ended_at`, `end_reason`, `duration_seconds`.
- INSERT `events`: `session.ended`.

---

## 7. Stats

### 7.1. `GET /api/v1/stats/user`

**Назначение:** сводная статистика пользователя.
**Аутентификация:** cookie.

**Query:** `from`, `to`, `limit`, `offset`.

**Response 200:** как в `GET /me/stats` + агрегаты по колодам.

**Ошибки:** 401, 422.

---

### 7.2. `GET /api/v1/stats/language-groups/:id`

**Назначение:** статистика по группе языков.
**Аутентификация:** cookie.

**Response 200:**
```json
{
  "language_group_id": "uuid",
  "language_code": "en",
  "decks_count": 4,
  "cards_count": 120,
  "cards_mastered": 30,
  "buckets": { "1": 20, "2": 25, "3": 20, "4": 20, "5": 15, "6": 20 },
  "daily": [
    { "day": "2025-01-15", "cards_viewed": 40, "time_total_ms": 540000 }
  ]
}
```

**Ошибки:** 401, 403, 404.

---

### 7.3. `GET /api/v1/stats/decks/:id`

**Назначение:** статистика по колоде.
**Аутентификация:** cookie.

**Response 200:**
```json
{
  "deck_id": "uuid",
  "cards_count": 40,
  "cards_mastered": 10,
  "buckets": { "1": 5, "2": 8, "3": 7, "4": 6, "5": 7, "6": 7 },
  "daily": [
    { "day": "2025-01-15", "cards_viewed": 20, "time_total_ms": 240000 }
  ],
  "sessions_count": 12
}
```

**Ошибки:** 401, 403, 404.

---

### 7.4. `GET /api/v1/stats/decks/:id/buckets`

**Назначение:** дневная динамика inflow/outflow по коробкам.
**Аутентификация:** cookie.

**Query:** `from`, `to`, `bucket` (1..6, optional).

**Response 200:**
```json
{
  "deck_id": "uuid",
  "items": [
    { "day": "2025-01-15", "bucket": 1, "inflow": 5, "outflow": 3 },
    { "day": "2025-01-15", "bucket": 2, "inflow": 3, "outflow": 2 }
  ]
}
```

**Ошибки:** 401, 403, 404, 422.

---

### 7.5. `GET /api/v1/stats/cards/:id`

**Назначение:** статистика карточки (алиас `GET /cards/:id/stats`).
**Аутентификация:** cookie.

**Response 200:** как в 5.8.

**Ошибки:** 401, 403, 404.

---

## 8. Admin (`/admin-{random}`)

> Все admin-эндпоинты требуют admin-сессию (`admin_sessions`) + TOTP + CSRF. Rate-limit: 60/мин/admin.

### 8.1. `POST /admin-{random}/login`

**Назначение:** вход администратора.
**Аутентификация:** public.

**Request body:**
```json
{
  "email": "string",
  "password": "string",
  "totp_code": "string (6 цифр)"
}
```

**Response 200:** `{ "admin_session": "uuid", "expires_at": "ISO8601", "csrf_token": "string" }`

**Ошибки:** 401, 403 (`NOT_ADMIN`), 422, 429.

**Побочные эффекты:** INSERT `admin_sessions`; INSERT `admin_audit`; INSERT `events`: `admin.login`.

---

### 8.2. `GET /admin-{random}/dashboard`

**Назначение:** сводка метрик.
**Аутентификация:** admin.

**Response 200:**
```json
{
  "users_total": 1234,
  "users_active_7d": 320,
  "sessions_today": 450,
  "events_today": 12000,
  "top_languages": [{"code":"en","count":800}]
}
```

**Ошибки:** 401, 403.

---

### 8.3. `GET /admin-{random}/users`

**Назначение:** список пользователей с фильтрами.
**Аутентификация:** admin.

**Query:** `q` (email/display_name), `is_blocked`, `email_verified`, `sort`, `order`, `limit`, `offset`.

**Response 200:** пагинированный список пользователей (id, email, display_name, is_blocked, email_verified, last_login_at, created_at).

**Ошибки:** 401, 403, 422.

---

### 8.4. `GET /admin-{random}/analytics`

**Назначение:** аналитика (page_views, events).
**Аутентификация:** admin.

**Query:** `from`, `to`, `path`, `device_type`, `country`, `event_type`.

**Response 200:** агрегаты по дням.

**Ошибки:** 401, 403, 422.

---

### 8.5. `GET /admin-{random}/words`

**Назначение:** модерация карточек/слов (поиск, блокировка).
**Аутентификация:** admin.

**Query:** `q` (trgm по front), `user_id`, `deck_id`, `limit`, `offset`.

**Response 200:** список карточек с контекстом.

**Ошибки:** 401, 403, 422.

---

### 8.6. `GET /admin-{random}/logs`

**Назначение:** логи (login_history, admin_audit, events).
**Аутентификация:** admin.

**Query:** `type` (`login|admin|event`), `user_id`, `from`, `to`, `limit`, `offset`.

**Response 200:** пагинированный список.

**Ошибки:** 401, 403, 422.

---

### 8.7. `GET /admin-{random}/security`

**Назначение:** безопасность (блокировки, неудачные входы, rate-limit hits).
**Аутентификация:** admin.

**Response 200:**
```json
{
  "locked_accounts": 3,
  "failed_logins_24h": 120,
  "rate_limit_hits_24h": 45,
  "blocked_ips": ["1.2.3.4"]
}
```

**Ошибки:** 401, 403.

---

## 9. Сводная таблица побочных эффектов

| Событие | events.event_type | Затрагиваемые агрегаты |
|---|---|---|
| Регистрация | `auth.register` | users, email_verifications |
| Подтверждение email | `auth.email_verified` | users |
| Вход | `auth.login_success` | users, login_history |
| Неудачный вход | `auth.login_failed` | users.failed_login_count, login_history |
| Выход | `auth.logout` | — |
| Сброс пароля | `auth.password_reset` | users, email_verifications |
| Создание группы | `language_group.created` | language_groups |
| Удаление группы | `language_group.deleted` | language_groups, decks, cards |
| Создание колоды | `deck.created` | decks, deck_bucket_progress |
| Обновление колоды | `deck.updated` | decks |
| Удаление колоды | `deck.deleted` | decks, cards, deleted_cards, card_stats, deck_bucket_progress, bucket_stats |
| Перемешивание колоды | `deck.shuffled` | cards.position (вся колода), decks.caret_position = 1 |
| Создание карточки | `card.created` | cards, decks.cards_count, card_stats, deck_bucket_progress, bucket_stats |
| Обновление карточки | `card.updated` | cards, card_stats.edits_count |
| Удаление карточки | `card.deleted` | cards, deleted_cards, decks.cards_count, card_stats, deck_bucket_progress, bucket_stats |
| Старт сессии | `session.started` | learning_sessions, user_daily_stats.sessions_count |
| Конец сессии | `session.ended` | learning_sessions |
| Просмотр | — (только `card_session_history`) | card_session_history, card_stats, learning_sessions, user_daily_stats |
| Переворот | — (только `card_session_history`) | card_session_history, card_stats |
| Свайп | — (только `card_session_history`) | card_session_history, card_stats, learning_sessions, user_daily_stats, cards.bucket, deck_bucket_progress, bucket_stats |
| Отмена свайпа | — (только `card_session_history`) | те же (обратные) |
| Смена коробки | `card.bucket_changed` | cards.bucket, deck_bucket_progress, bucket_stats (**status не меняется**) |
| Смена статуса | `card.status_changed` | cards.status, card_stats.mastered_at, user_daily_stats.cards_mastered |
| Удаление аккаунта | `user.deleted` | users, deleted_users |

---

## 10. OpenAPI

Полная OpenAPI 3.1-схема генерируется FastAPI автоматически и доступна по `/api/v1/openapi.json`. Документ `api.md` — источник истины для ручного ревью контрактов.