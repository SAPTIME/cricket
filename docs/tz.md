# Техническое задание
## SaaS-сервис для изучения иностранных слов «Сверчок / Cricket»

**Версия документа:** 1.0
**Статус:** финальное ТЗ для MVP
**Дата:** 2026-09-22

---

# Часть 1. Общие сведения о продукте

## 1.1. Назначение

«Сверчок» — веб-приложение (mobile-first) для изучения иностранных слов через карточки с методом интервального повторения на основе коробок Лейтнера. Бесплатный B2C-сервис с последующей монетизацией через рекламу полезных сервисов и премиум-функции.

## 1.2. Целевая аудитория

- Школьники и студенты.
- Взрослые, изучающие язык самостоятельно.
- Преподаватели (в будущем, вне MVP).

## 1.3. Ключевые ценности

1. **Простота** — минимум действий, чтобы начать учить слова.
2. **Mobile-first** — основной сценарий на телефоне.
3. **Чистый режим обучения** — никакой отвлекающей информации.
4. **Прозрачная статистика** — отдельный режим редактирования с полной аналитикой.
5. **Бесплатно** — базовый функционал без ограничений.

## 1.4. Метрики успеха MVP

| Метрика | Цель |
|---|---|
| Регистрация → первая карточка | ≥ 60% |
| Первая карточка → первая сессия обучения | ≥ 80% |
| Retention D1 | ≥ 30% |
| Retention D7 | ≥ 15% |
| Среднее число сессий на пользователя в неделю | ≥ 3 |
| Среднее число карточек в колоде | ≥ 20 |

---

# Часть 2. Скоуп MVP

## 2.1. Входит в MVP

- Регистрация с подтверждением email, вход, выход, сброс пароля.
- Профиль: аватар, имя, никнейм, часовой пояс, город, родной язык, настройки рассылок, тема.
- Группы языков (создание, удаление).
- Колоды карточек внутри группы языка (создание, редактирование, удаление, перемешивание).
- Карточки: несколько переводов, до 3 транскрипций, пары «пример + перевод».
- Коробки: День, Неделя, Месяц, Год. Ручное перемещение.
- Статусы: Новая, Изучается, Выучена (архив), Удалена.
- Режим обучения: forward/backward, свайпы, переворот, таймер, возврат к предыдущей карточке.
- Статистика: по карточке, колоде, языку, пользователю, коробкам.
- Режим редактирования с табличным отображением и статистикой.
- Админ-панель: пользователи, контент, аналитика, логи, безопасность.
- Лендинг (статичный).
- Политика конфиденциальности и оферта (типовые шаблоны).
- i18n-каркас (только русский интерфейс на старте).
- Тёмная/светлая тема.
- Адаптивная вёрстка (mobile-first).

## 2.2. Не входит в MVP

- OAuth (Google, Apple).
- Офлайн-режим.
- Медиа в карточках (аудио, изображения).
- TTS и озвучка.
- Части речи, теги.
- Копирование карточек между колодами.
- Автоматическая сортировка по SRS-алгоритму.
- Рекомендации и упражнения.
- Публичные колоды, шеринг.
- Экспорт данных.
- Фоновые задачи (рассылки «пора повторить»).
- Мобильные приложения (только PWA-манифест).
- Платёжные системы.
- 2FA для обычных пользователей.

---

# Часть 3. Роли и права

| Роль | Описание | Права |
|---|---|---|
| **Гость** | Неавторизованный пользователь | Лендинг, регистрация, вход, сброс пароля |
| **Пользователь** | Авторизованный | Всё, кроме админки |
| **Админ** | Сотрудник сервиса | Админ-панель + всё, что у пользователя |

**Особенности админа:**
- Вход через отдельный секретный URL.
- TOTP-2FA обязателен.
- IP allowlist (настраиваемый).
- Отдельная таблица сессий с коротким TTL.
- Все действия логируются в `admin_audit`.

---

# Часть 4. Доменная модель

## 4.1. Иерархия

```
User
 └── LanguageGroup (изучаемый язык)
      └── Deck (пара языков: изучаемый ↔ язык перевода)
           └── Card
```

**Правила:**
- 1 пользователь = 1 аккаунт.
- 1 карточка принадлежит строго 1 колоде.
- 1 колода принадлежит строго 1 группе языка и одной языковой паре.
- 1 колода = 1 пара `target_language ↔ translation_language`.
- Группа языка удаляется только при отсутствии колод.

## 4.2. Сущности

### User
Пользователь системы.

### LanguageGroup
Группа языка — контейнер для колод и агрегатор статистики по языку.

### Deck
Колода карточек — единица организации слов (например, «Учебник English File», «Слова к интервью»).

### Card
Карточка слова или выражения.

### Bucket (enum)
Коробка: `day`, `week`, `month`, `year`.

### LearningState (enum)
Статус: `new`, `learning`, `mastered`.

### Direction (enum)
Направление обучения: `forward` (слово → перевод), `backward` (перевод → слово).

### LearningSession
Сессия обучения.

### CardSessionHistory
История участия карточки в сессиях.

### BucketStats
Дневные агрегаты по коробкам.

### UserDailyStats
Дневные агрегаты пользователя.

### Event
Журнал важных событий.

### PageView
Просмотры экранов (для рекламной аналитики).

### DeletedCard / DeletedUser
Архивные сущности.

---

# Часть 5. Схема базы данных

**СУБД:** PostgreSQL 16
**Кодировка:** UTF-8
**Все timestamp:** `timestamptz` (хранение в UTC)
**Все ID:** `uuid` (кроме event/pageview — `bigserial`)
**Партиционирование:** `events`, `page_views`, `card_session_history` — по месяцам

## 5.1. users

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| email | citext UNIQUE NOT NULL | |
| username | citext UNIQUE NOT NULL | |
| display_name | text | |
| password_hash | text NOT NULL | argon2id |
| avatar_path | text | |
| timezone | text NOT NULL | IANA, напр. Europe/Moscow |
| utc_offset_minutes | int | |
| dst | bool | признак перехода на летнее время |
| city | text | |
| native_language_code | char(2) | FK → languages.code |
| interface_language | char(2) DEFAULT 'ru' | |
| theme | text DEFAULT 'light' | light/dark |
| email_notifications | bool DEFAULT true | |
| email_verified_at | timestamptz | |
| is_admin | bool DEFAULT false | |
| is_active | bool DEFAULT true | |
| failed_login_attempts | int DEFAULT 0 | |
| locked_until | timestamptz | |
| last_login_at | timestamptz | |
| created_at | timestamptz NOT NULL DEFAULT now() | |
| updated_at | timestamptz NOT NULL DEFAULT now() | |

**Индексы:** `email`, `username`, `is_active`, `is_admin`.

## 5.2. languages (справочник)

| Поле | Тип | Описание |
|---|---|---|
| code | char(2) PK | ISO 639-1 |
| name_ru | text | Русское название |
| name_en | text | Английское название |
| native_name | text | Самоназвание |

Заливается на старте: ~180 языков.

## 5.3. language_groups

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK → users | ON DELETE CASCADE |
| language_code | char(2) FK → languages | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

**Уникальность:** `(user_id, language_code)`.
**Индекс:** `user_id`.

## 5.4. decks

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK → users | |
| language_group_id | uuid FK → language_groups | ON DELETE RESTRICT |
| target_language_code | char(2) | изучаемый |
| translation_language_code | char(2) | язык перевода |
| name | text NOT NULL | |
| description | text | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

**Индексы:** `user_id`, `language_group_id`.

## 5.5. cards

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| deck_id | uuid FK → decks | ON DELETE CASCADE |
| user_id | uuid FK → users | |
| word | text NOT NULL | |
| transcriptions | jsonb | массив до 3 строк |
| translations | jsonb | массив строк |
| examples | jsonb | массив `{sentence, translation}` |
| bucket | text NOT NULL DEFAULT 'day' | day/week/month/year |
| learning_state | text NOT NULL DEFAULT 'new' | new/learning/mastered |
| position | int NOT NULL | порядок в колоде |
| views_count | int DEFAULT 0 | |
| flips_to_back_count | int DEFAULT 0 | |
| flips_to_front_count | int DEFAULT 0 | |
| swipes_left_count | int DEFAULT 0 | |
| swipes_right_count | int DEFAULT 0 | |
| edits_count | int DEFAULT 0 | |
| time_front_ms | bigint DEFAULT 0 | |
| time_back_ms | bigint DEFAULT 0 | |
| sessions_count | int DEFAULT 0 | |
| first_viewed_at | timestamptz | |
| last_viewed_at | timestamptz | |
| mastered_at | timestamptz | |
| created_at | timestamptz | |
| updated_at | timestamptz | |

**Индексы:** `(deck_id, position)`, `(deck_id, bucket)`, `(user_id, learning_state)`, `created_at`.

## 5.6. card_stats (по направлениям)

| Поле | Тип | Описание |
|---|---|---|
| card_id | uuid FK → cards | |
| direction | text | forward/backward |
| views_count | int DEFAULT 0 | |
| flips_to_back | int DEFAULT 0 | |
| flips_to_front | int DEFAULT 0 | |
| swipes_left | int DEFAULT 0 | |
| swipes_right | int DEFAULT 0 | |
| time_front_ms | bigint DEFAULT 0 | |
| time_back_ms | bigint DEFAULT 0 | |
| sessions_count | int DEFAULT 0 | |
| first_viewed_at | timestamptz | |
| last_viewed_at | timestamptz | |

**PK:** `(card_id, direction)`.

## 5.7. deck_bucket_progress (каретка)

| Поле | Тип | Описание |
|---|---|---|
| deck_id | uuid FK | |
| bucket | text | day/week/month/year/all |
| direction | text | forward/backward |
| last_position | int DEFAULT 0 | |
| updated_at | timestamptz | |

**PK:** `(deck_id, bucket, direction)`.

## 5.8. learning_sessions

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK | |
| deck_id | uuid FK | |
| bucket | text | day/week/month/year/all |
| direction | text | forward/backward |
| started_at | timestamptz | |
| ended_at | timestamptz | |
| last_activity_at | timestamptz | |
| cards_reviewed | int DEFAULT 0 | |
| duration_ms | bigint DEFAULT 0 | |
| swipes_left | int DEFAULT 0 | |
| swipes_right | int DEFAULT 0 | |
| reverts_count | int DEFAULT 0 | |
| is_completed | bool DEFAULT false | |

**Индексы:** `(user_id, started_at)`, `deck_id`.

## 5.9. card_session_history (партиционировано по viewed_at)

| Поле | Тип | Описание |
|---|---|---|
| id | bigserial | |
| card_id | uuid | |
| session_id | uuid | |
| user_id | uuid | |
| direction | text | |
| viewed_at | timestamptz NOT NULL | ключ партиционирования |
| swipe | text | left/right/null |
| reverted | bool DEFAULT false | |
| time_front_ms | bigint | |
| time_back_ms | bigint | |
| flips_count | int | |

**PK:** `(id, viewed_at)`.
**Индексы:** `(card_id, viewed_at)`, `(session_id)`, `(user_id, viewed_at)`.

## 5.10. bucket_stats (дневные агрегаты)

| Поле | Тип | Описание |
|---|---|---|
| user_id | uuid | |
| deck_id | uuid | |
| bucket | text | |
| date | date | |
| inflow | int DEFAULT 0 | |
| outflow | int DEFAULT 0 | |
| net_change | int DEFAULT 0 | |

**PK:** `(user_id, deck_id, bucket, date)`.

## 5.11. user_daily_stats

| Поле | Тип | Описание |
|---|---|---|
| user_id | uuid | |
| date | date | |
| sessions_count | int DEFAULT 0 | |
| cards_viewed | int DEFAULT 0 | |
| time_spent_ms | bigint DEFAULT 0 | |
| swipes_left | int DEFAULT 0 | |
| swipes_right | int DEFAULT 0 | |
| logins_count | int DEFAULT 0 | |

**PK:** `(user_id, date)`.

## 5.12. events (партиционировано по created_at)

| Поле | Тип | Описание |
|---|---|---|
| id | bigserial | |
| user_id | uuid | |
| event_type | text NOT NULL | |
| entity_type | text | |
| entity_id | uuid | |
| payload | jsonb | |
| session_id | uuid | |
| ip | inet | |
| user_agent | text | |
| created_at | timestamptz NOT NULL | ключ партиционирования |

**PK:** `(id, created_at)`.
**Индексы:** `(user_id, created_at)`, `(event_type, created_at)`, `(entity_type, entity_id)`.

**Типы событий:**
```
user.registered, user.email_verified, user.logged_in, user.logged_out,
user.password_changed, user.profile_updated, user.deleted,
language_group.created, language_group.deleted,
deck.created, deck.updated, deck.deleted,
card.created, card.updated, card.deleted,
card.status_changed, card.bucket_changed, card.swipe_reverted,
session.started, session.ended
```

**Что НЕ пишем в events:** каждый свайп, каждый переворот, каждое открытие карточки — только в агрегаты.

## 5.13. page_views (партиционировано по created_at)

| Поле | Тип | Описание |
|---|---|---|
| id | bigserial | |
| user_id | uuid NULL | для анонимных |
| session_id | uuid | |
| path | text | |
| screen_name | text | |
| referrer | text | |
| ip | inet | |
| user_agent | text | |
| device_type | text | mobile/tablet/desktop |
| os | text | |
| browser | text | |
| country | char(2) | |
| created_at | timestamptz NOT NULL | ключ партиционирования |

## 5.14. deleted_cards (гибрид)

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| original_id | uuid | |
| user_id | uuid | |
| deck_id | uuid | |
| deck_name_historical | text | |
| language_group_name_historical | text | |
| word | text | |
| translation | text | |
| bucket | text | |
| learning_state | text | |
| payload | jsonb | транскрипции, примеры, статистика, история сессий |
| created_at | timestamptz | |
| deleted_at | timestamptz | |

## 5.15. deleted_users

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| original_id | uuid | |
| email | citext | |
| username | citext | |
| payload | jsonb | полный дамп |
| deleted_at | timestamptz | |

## 5.16. email_verifications

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK | |
| email | citext | |
| code_hash | text | |
| purpose | text | registration/password_reset/email_change |
| expires_at | timestamptz | |
| used_at | timestamptz | |
| created_at | timestamptz | |

## 5.17. login_history

| Поле | Тип | Описание |
|---|---|---|
| id | bigserial | |
| user_id | uuid | |
| ip | inet | |
| user_agent | text | |
| browser | text | |
| os | text | |
| timezone | text | |
| success | bool | |
| created_at | timestamptz | |

## 5.18. admin_sessions

| Поле | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK | |
| token_hash | text | |
| ip | inet | |
| user_agent | text | |
| totp_verified | bool | |
| created_at | timestamptz | |
| expires_at | timestamptz | |

## 5.19. admin_audit

| Поле | Тип | Описание |
|---|---|---|
| id | bigserial | |
| admin_id | uuid | |
| action | text | |
| entity_type | text | |
| entity_id | uuid | |
| payload | jsonb | |
| ip | inet | |
| created_at | timestamptz | |

## 5.20. landing_content

| Поле | Тип | Описание |
|---|---|---|
| key | text PK | |
| value | text | |
| updated_at | timestamptz | |

Резервная таблица, если решим редактировать лендинг из админки в будущем.

---

# Часть 6. Событийная модель и агрегаты

## 6.1. Принцип

**Гибридная модель:**
- **Агрегаты** пишутся в той же транзакции, что и действие. Это источник быстрых отчётов.
- **Event log** — только важные события (создание, удаление, смена статуса, смена коробки, безопасность). Партиционируется по месяцам.

## 6.2. Формулы агрегатов

### При просмотре карточки (view)
```
cards.views_count += 1
cards.first_viewed_at = COALESCE(first_viewed_at, now())
cards.last_viewed_at = now()
card_stats[card_id, direction].views_count += 1
```

### При перевороте (flip)
```
if direction of flip == to_back:
  cards.flips_to_back_count += 1
  card_stats[card_id, dir].flips_to_back += 1
else:
  cards.flips_to_front_count += 1
  card_stats[card_id, dir].flips_to_front += 1
```

### При свайпе (swipe)
```
if swipe == left:
  cards.swipes_left_count += 1
  sessions.swipes_left += 1
else:
  cards.swipes_right_count += 1
  sessions.swipes_right += 1
```

### При возврате и изменении свайпа (revert)
```
events: card.swipe_reverted (payload: old_swipe, new_swipe, session_id)
агрегаты: вычесть старое значение, прибавить новое
```

### При смене коробки (bucket_changed)
```
bucket_stats[user, deck, old_bucket, today].outflow += 1
bucket_stats[user, deck, old_bucket, today].net_change -= 1
bucket_stats[user, deck, new_bucket, today].inflow += 1
bucket_stats[user, deck, new_bucket, today].net_change += 1
events: card.bucket_changed
```

### При смене статуса (status_changed)
```
if new == 'mastered':
  cards.mastered_at = now()
  cards.bucket = NULL  (карточка уходит из всех коробок)
events: card.status_changed
```

### При удалении карточки
```
- вычесть все агрегаты карточки из cards, card_stats, bucket_stats, user_daily_stats
- перенести в deleted_cards
events: card.deleted
```

## 6.3. Правила отмены (revert)

- Возврат возможен только к карточкам **текущей сессии**, по которым уже был свайп.
- Если свайп не изменён — ничего не пишем.
- Если изменён — пишем `card.swipe_reverted`, пересчитываем агрегаты.
- Просмотр при возврате **не считается** повторным.

---

# Часть 7. API-контракты (REST)

**Базовый URL:** `/api/v1`
**Формат:** JSON
**Аутентификация:** HttpOnly cookie (session)
**CSRF:** заголовок `X-CSRF-Token` для всех POST/PUT/PATCH/DELETE

## 7.1. Auth

| Метод | Endpoint | Описание |
|---|---|---|
| POST | `/auth/register` | Регистрация |
| POST | `/auth/verify-email` | Подтверждение email кодом |
| POST | `/auth/resend-code` | Повторная отправка кода |
| POST | `/auth/login` | Вход |
| POST | `/auth/logout` | Выход |
| POST | `/auth/forgot-password` | Запрос на сброс |
| POST | `/auth/reset-password` | Сброс пароля с кодом |
| POST | `/auth/change-password` | Смена пароля из профиля |

## 7.2. Profile

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/me` | Текущий пользователь |
| PATCH | `/me` | Обновление профиля |
| POST | `/me/avatar` | Загрузка аватара |
| DELETE | `/me` | Soft-delete аккаунта |
| GET | `/me/stats` | Сводная статистика |

## 7.3. Languages

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/languages` | Справочник |
| GET | `/language-groups` | Список групп |
| POST | `/language-groups` | Создать |
| DELETE | `/language-groups/:id` | Удалить (только если нет колод) |

## 7.4. Decks

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/decks` | Список |
| POST | `/decks` | Создать |
| GET | `/decks/:id` | Детали |
| PATCH | `/decks/:id` | Обновить |
| DELETE | `/decks/:id` | Удалить (каскадно) |
| POST | `/decks/:id/shuffle` | Перемешать |

## 7.5. Cards

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/decks/:id/cards` | Список с фильтрами |
| POST | `/decks/:id/cards` | Создать |
| GET | `/cards/:id` | Детали |
| PATCH | `/cards/:id` | Обновить |
| DELETE | `/cards/:id` | Удалить |
| POST | `/cards/:id/bucket` | Сменить коробку |
| POST | `/cards/:id/status` | Сменить статус |
| GET | `/cards/:id/stats` | Статистика |

## 7.6. Learning

| Метод | Endpoint | Описание |
|---|---|---|
| POST | `/sessions/start` | Начать сессию |
| GET | `/sessions/:id/next` | Следующая карточка |
| POST | `/sessions/:id/view` | Зафиксировать просмотр |
| POST | `/sessions/:id/flip` | Зафиксировать переворот |
| POST | `/sessions/:id/swipe` | Свайп |
| POST | `/sessions/:id/revert` | Возврат к предыдущей |
| POST | `/sessions/:id/end` | Завершить |

## 7.7. Stats

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/stats/user` | Статистика пользователя |
| GET | `/stats/language-groups/:id` | По языку |
| GET | `/stats/decks/:id` | По колоде |
| GET | `/stats/decks/:id/buckets` | По коробкам |
| GET | `/stats/cards/:id` | По карточке |

## 7.8. Admin

Все эндпоинты за секретным префиксом `/admin-{random}/`.

| Метод | Endpoint | Описание |
|---|---|---|
| GET/POST | `/login` | Вход с TOTP |
| GET | `/dashboard` | Дашборд |
| GET | `/users` | Список |
| GET | `/users/:id` | Детали |
| POST | `/users/:id/block` | Блокировка |
| GET | `/analytics` | Рекламная аналитика |
| GET | `/words` | Статистика слов |
| GET | `/logs` | Логи |
| GET | `/security` | Безопасность |

---

# Часть 8. UI/UX

## 8.1. Карта экранов

**Публичные:**
- Лендинг
- Регистрация
- Подтверждение email
- Вход
- Сброс пароля

**Пользователь:**
- Главная (дашборд со сводкой)
- Профиль
- Настройки
- Группы языков (список)
- Колоды (список внутри языка)
- Карточки колоды (режим редактирования, таблица)
- Карточка (создание/редактирование)
- Экран запуска сессии (выбор колоды, коробки, направления, перемешать)
- Экран обучения (карточка, свайпы)
- Архив (mastered)
- Статистика: пользователь, язык, колода, коробка, карточка
- Удалённые карточки

**Админ:**
- Дашборд
- Пользователи
- Аналитика
- Слова
- Логи
- Безопасность
- Контент

## 8.2. Экран обучения

**Отображается:**
- Карточка (лицевая / оборотная сторона).
- Прогресс-бар.
- Таймер сессии.
- Счётчик просмотренных карточек.
- Кнопки: ← Не помню | Перевернуть | Помню →
- Кнопка «Назад» (возврат к предыдущей).

**Скрыто:** вся статистика, счётчики свайпов, время на стороны.

**Жесты:**
- Тап по карточке — переворот.
- Свайп влево — «не помню».
- Свайп вправо — «помню».

**Горячие клавиши (настраиваемые в профиле):**
- `Space` / `Enter` — перевернуть.
- `←` — не помню.
- `→` — помню.
- `Backspace` / `Z` — назад.
- `Esc` — выйти.
- `R` — перемешать.

## 8.3. Режим редактирования

- Таблица карточек: слово, перевод, коробка, статус, счётчики (просмотры, свайпы, перевороты, редактирования).
- Фильтры: по коробке, по статусу, по дате.
- Пагинация.
- Мобильная вёрстка: карточки-строки с раскрытием.
- Кнопка «Перемешать».
- Кнопка «Статистика колоды» (графики).

## 8.4. Адаптивность

- Mobile-first: базовые стили для телефона, медиа-запросы для планшета и десктопа.
- Тач-жесты через Swiper.js.
- Тёмная/светлая тема (переключатель в профиле, дефолт — светлая).

---

# Часть 9. Логика обучения

## 9.1. Сессия

- **Старт:** пользователь выбирает колоду, коробку, направление, опционально — перемешать.
- **Направление:** forward (слово → перевод) или backward (перевод → слово). Смешивать нельзя.
- **Порядок:** по `position`, начиная с `last_position + 1`. При отсутствии — с начала.
- **Перемешивание:** пересчёт `position`, каретка → 1.
- **Таймаут:** 10 минут простоя → сессия закрывается. Продолжить нельзя — новая сессия с каретки.
- **Возврат:** только к карточкам текущей сессии, по которым уже был свайп. Максимум — до первой. Вперёд — только через свайп текущей.
- **Завершение:** вручную или по таймауту.

## 9.2. Статусы

| Статус | Описание | Переходы |
|---|---|---|
| new | Не смотрел | → learning (авто), → mastered (вручную) |
| learning | Смотрел, не выучен | → mastered (вручную) |
| mastered | Выучен, в архиве | → new (вручную, коробка → День) |
| deleted | Удалён | — |

**Правила:**
- `learning → new` запрещён.
- `mastered → learning` не существует.
- `mastered → new` — коробка сбрасывается в `day`.

## 9.3. Коробки

Фиксированные: `day`, `week`, `month`, `year`. Виртуальная `all` — для отображения всех карточек колоды.

**Правила:**
- Не влияют на статус.
- Перемещаются только вручную.
- Автоматизации нет.
- Новая карточка по умолчанию — `day`, пользователь может выбрать другую.

## 9.4. Каретка

- Хранится в `deck_bucket_progress` для каждой `(deck_id, bucket, direction)`.
- При перемешивании — сбрасывается в 1.
- При удалении карточки — не сдвигается. При открытии сессии берётся ближайшая `position > каретки`. Иначе — с начала.

---

# Часть 10. Статистика

## 10.1. Уровни

1. **Пользователь** — сводная (streak, всего слов, mastered, время).
2. **Язык** — агрегаты по группе языка.
3. **Колода** — прогресс, воронка, распределение по коробкам.
4. **Коробка** — inflow/outflow, net change.
5. **Карточка** — детально по направлениям, счётчики, история сессий.

## 10.2. Что собираем

**По карточке:**
- Просмотры, перевороты (в обе стороны), свайпы (в обе стороны), редактирования.
- Суммарное время на лицевую и оборотную сторону.
- Количество сессий.
- История: какие сессии, с каким результатом.

**По сессии:**
- Длительность, число карточек, свайпы, возвраты.

**По коробкам:**
- Сколько карточек пришло/ушло за день, net change.

**По пользователю:**
- DAU/WAU/MAU, streak, время, конверсия.

**Для рекламы (админ):**
- Page views по экранам, устройства, ОС, браузеры, гео.
- Время на экране, глубина сессии.
- Уникальные посетители, bounce rate.

## 10.3. Отображение

- **Режим обучения:** только таймер сессии и счётчик просмотров.
- **Режим редактирования:** полная статистика.
- **Личный кабинет:** сводка по пользователю.
- **Админ:** все отчёты.

---

# Часть 11. Безопасность

## 11.1. Аутентификация

- Пароль: **argon2id**.
- Cookie: **HttpOnly + Secure + SameSite=Lax**.
- CSRF-токен для всех POST/PUT/PATCH/DELETE.
- Rate limit на логин: 5 попыток → блокировка + email-уведомление.
- Rate limit на регистрацию и сброс пароля по IP.
- Логирование всех auth-событий.

## 11.2. Транспорт

- HTTPS обязателен (Let's Encrypt).
- Заголовки: CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, HSTS.

## 11.3. Валидация

- Pydantic v2 для всех входных данных.
- Jinja2 auto-escape.
- Ограничение размера payload (nginx `client_max_body_size 2m`).

## 11.4. Секреты

- `.env` файл, не в репозитории.
- Разные секреты для dev/prod.

## 11.5. Админ

- Секретный URL (`/admin-{random}/`).
- TOTP-2FA обязателен.
- IP allowlist.
- Отдельные сессии с коротким TTL.
- Все действия в `admin_audit`.

---

# Часть 12. i18n

- Все строки в `locales/{lang}.json`.
- Обёртка `_("key")` в шаблонах и коде.
- При старте приложение сканирует папку `locales/`, определяет доступные языки, предлагает выбор.
- Дефолт: `ru`.
- В админке — редактор словарей.

---

# Часть 13. Админ-панель

## 13.1. Разделы

1. **Дашборд:** DAU/WAU/MAU, регистрации, retention, RPS, топ-ошибки.
2. **Пользователи:** поиск, блокировка, статистика, soft-delete.
3. **Аналитика для рекламы:** page views, устройства, гео, bounce rate, экспорт CSV.
4. **Слова:** топ по частоте, по сложности, «застрявшие».
5. **Логи:** разделение по платформе (backend/frontend/db/admin/security), поиск, фильтр.
6. **Безопасность:** попытки входа, блокировки, подозрительные IP.
7. **Контент:** справочник языков, тексты лендинга, email-шаблоны, i18n-словари.

## 13.2. Логи

- **Файлы:** JSON, ротация по дням, отдельные файлы по платформам.
- **БД:** только security-события (для быстрого поиска и алертов).
- Хранение в БД: 30 дней. Дальше — файлы.

---

# Часть 14. Лендинг и юридические тексты

## 14.1. Лендинг

Статичный Jinja2-шаблон. i18n через словари. Кнопки «Войти» / «Регистрация» ведут в приложение.

**Хедер:** Логотип | Главная | О сервисе | Стоимость | Советы | О команде | Контакты | Войти | Попробовать.

**Секции:**
1. Hero с анимированной карточкой.
2. Как это работает (3 шага).
3. Почему Сверчок (4 плитки).
4. Скриншоты (мобильные мокапы).
5. Цифры (счётчики).
6. Отзывы (3 карточки).
7. FAQ (аккордеон).
8. CTA.
9. Футер.

## 14.2. Юридические тексты

Типовые шаблоны для РФ (152-ФЗ):
- Политика конфиденциальности.
- Пользовательское соглашение (оферта).

**Пометка:** перед публикацией — проверка у юриста.

---

# Часть 15. Архитектура и DevOps

## 15.1. Стек

| Компонент | Технология |
|---|---|
| Backend | FastAPI + SQLAlchemy 2.0 (async) + Alembic + Pydantic v2 |
| БД | PostgreSQL 16 |
| Кэш/сессии/rate-limit | Redis 7 |
| Frontend | Jinja2 + HTMX + Alpine.js + Tailwind CSS + Swiper.js |
| Веб-сервер | Nginx |
| Контейнеризация | Docker + Docker Compose |
| Логи | JSON в файлы + security в БД |
| Мониторинг ошибок | Sentry |
| Бэкапы | pg_dump ежедневно → S3-совместимое хранилище |

## 15.2. Развёртывание

**Один VPS:**
- Nginx (reverse proxy, TLS).
- FastAPI (uvicorn, 4 воркера).
- PostgreSQL 16.
- Redis 7.
- Certbot для TLS.

**Бэкапы:**
- Ежедневный `pg_dump` → S3 / другой VPS.
- Хранение: 30 дней.

## 15.3. Масштабирование

| Пользователей | Что нужно |
|---|---|
| до 100 | 1 VPS (2 CPU, 4 GB RAM), Docker Compose |
| до 1 000 | 1 VPS (4 CPU, 8 GB RAM), Redis, PgBouncer |
| до 10 000 | Read-replica, Redis Cluster, вынос event log в отдельную БД |
| > 10 000 | Шардирование, ClickHouse, микросервисы, Kubernetes |

**Принципы для безболезненного роста:**
1. Абстракция репозиториев — переезд на ClickHouse/шардирование без правки кода.
2. Event bus — сейчас Postgres, потом Kafka/Redis Streams.
3. Stateless FastAPI — состояние в Redis/Postgres.
4. Партиционирование с первого дня.
5. Конфиг через `.env` — переключение реализаций.

## 15.4. Деплой

- На старте: вручную.
- CI/CD: позже (GitHub Actions).

---

# Часть 16. План спринтов

## Спринт 1 (2 недели). Скелет, auth, профиль, i18n

- Docker Compose, структура проекта, Alembic.
- Регистрация, подтверждение email, вход, выход, сброс пароля.
- CSRF, rate-limit, argon2.
- Профиль: просмотр, редактирование, аватар, темы.
- i18n-каркас, словарь `ru`.
- Базовый layout.

**Критерий:** пользователь регистрируется, подтверждает email, входит, редактирует профиль, выходит.

## Спринт 2 (2 недели). Языки, колоды, карточки

- Справочник языков (ISO 639-1).
- CRUD групп языков.
- CRUD колод.
- CRUD карточек (несколько переводов, до 3 транскрипций, пары примеров).
- Перемешивание колоды.
- Режим редактирования: таблица, фильтры, пагинация.

**Критерий:** пользователь создаёт язык, колоду, карточку, редактирует, удаляет.

## Спринт 3 (2 недели). Сессия обучения

- Экран запуска сессии (колода, коробка, направление, перемешать).
- Экран обучения: карточка, свайпы, переворот, таймер, счётчик.
- Горячие клавиши.
- Каретка, порядок, перемешивание.
- Возврат к предыдущей карточке, отмена свайпа.
- Таймаут 10 минут.
- Агрегаты: card_stats, session_stats, user_daily_stats.
- События: session.started, session.ended, card.swipe_reverted.

**Критерий:** пользователь запускает сессию, свайпает карточки, переворачивает, возвращается назад, меняет свайп, завершает сессию. Статистика записана.

## Спринт 4 (2 недели). Коробки, статусы, статистика

- Коробки: ручное перемещение, bucket_stats.
- Статусы: new → learning → mastered → new.
- Архив.
- Удаление карточек, колод, языков, пользователя.
- deleted_cards, deleted_users.
- Статистика: по карточке, колоде, языку, пользователю, коробке.
- Каретка, партиционирование events и card_session_history.

**Критерий:** пользователь перемещает карточки по коробкам, меняет статусы, смотрит статистику, удаляет.

## Спринт 5 (2 недели). Админка, аналитика, логи

- Админ-панель: секретный URL, TOTP, IP allowlist.
- Дашборд, пользователи, аналитика, слова, логи, безопасность, контент.
- Page views (для рекламной аналитики).
- Логи: файлы + security в БД.
- Sentry.

**Критерий:** админ входит, видит дашборд, управляет пользователями, смотрит аналитику и логи.

## Спринт 6 (2 недели). Лендинг, полировка, деплой

- Лендинг (все секции).
- Политика, оферта.
- Адаптивность: тесты на мобильных, планшетах, десктопе.
- Тёмная тема.
- Оптимизация запросов, индексы.
- Бэкапы.
- Деплой на VPS.

**Критерий:** продукт работает end-to-end на проде, все сценарии MVP покрыты.

---

# Часть 17. Открытые вопросы и риски

## 17.1. Открытые вопросы

1. Точный список текстов email (приветственное, подтверждение, сброс, уведомление о блокировке).
2. Финальный дизайн лендинга и иллюстрации.
3. Домен и финальное название.
4. Реквизиты для оферты.
5. Брендинг (логотип, цвета, шрифты).

## 17.2. Риски

| Риск | Митигация |
|---|---|
| Рост event log | Партиционирование с первого дня, вынос в отдельную БД при 10k+ |
| Свайпы на мобильных | Swiper.js, тесты на iOS/Android |
| Таймзоны и DST | Храним IANA + UTC offset + DST, все timestamp в UTC |
| Потеря данных | Ежедневный pg_dump, тесты восстановления |
| Безопасность | argon2, CSRF, rate-limit, TOTP для админа, IP allowlist |
| Производительность при росте | Абстракция репозиториев, Redis, партиционирование |
| Юридические тексты | Шаблоны + проверка у юриста |
| Партиционирование миграций | Alembic + ручные скрипты для партиций |

---

# Часть 18. Глоссарий

| Термин | Значение |
|---|---|
| **Колода (Deck)** | Набор карточек по одной языковой паре |
| **Группа языка (LanguageGroup)** | Контейнер для колод одного языка |
| **Коробка (Bucket)** | Уровень интервального повторения: день/неделя/месяц/год |
| **Статус (LearningState)** | new / learning / mastered |
| **Направление (Direction)** | forward (слово → перевод) / backward (перевод → слово) |
| **Каретка** | Номер последней изученной карточки в колоде+коробке+направлении |
| **Сессия обучения** | Один подход пользователя к изучению карточек |
| **Свайп** | Жест влево (не помню) / вправо (помню) |
| **Переворот** | Показ оборотной стороны карточки |
| **Revert** | Возврат к предыдущей карточке и изменение свайпа |
| **SRS** | Spaced Repetition System — система интервального повторения |
| **TOTP** | Time-based One-Time Password (Google Authenticator) |

---

**Конец документа.**
