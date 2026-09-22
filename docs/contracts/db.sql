-- ============================================================================
-- «Сверчок» — схема базы данных
-- Документ: /docs/contracts/db.sql
-- Версия: 1.0
-- PostgreSQL 16
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Расширения
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- Схема для партиций (опционально; используем public)
-- ---------------------------------------------------------------------------
-- Все таблицы в public.

-- ============================================================================
-- ЧАСТЬ 1. СПРАВОЧНИКИ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- languages — справочник языков ISO 639-1
-- ---------------------------------------------------------------------------
CREATE TABLE languages (
    code            char(2) PRIMARY KEY,
    code_alpha3     char(3) NOT NULL,
    name_ru         text NOT NULL,
    name_en         text NOT NULL,
    native_name     text,
    created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  languages IS 'Справочник языков ISO 639-1 (двухбуквенные коды)';
COMMENT ON COLUMN languages.code IS 'ISO 639-1 (2 буквы)';
COMMENT ON COLUMN languages.code_alpha3 IS 'ISO 639-2/3 (3 буквы)';
COMMENT ON COLUMN languages.name_ru IS 'Название на русском';
COMMENT ON COLUMN languages.name_en IS 'Название на английском';
COMMENT ON COLUMN languages.native_name IS 'Самоназвание';

CREATE UNIQUE INDEX ux_languages_alpha3 ON languages (code_alpha3);
CREATE INDEX ix_languages_name_ru_trgm ON languages USING gin (name_ru gin_trgm_ops);
CREATE INDEX ix_languages_name_en_trgm ON languages USING gin (name_en gin_trgm_ops);

-- ============================================================================
-- ЧАСТЬ 2. ПОЛЬЗОВАТЕЛИ И АУТЕНТИФИКАЦИЯ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email               citext NOT NULL,
    password_hash       text NOT NULL,
    display_name        text,
    avatar_url          text,
    email_verified_at   timestamptz,
    is_blocked          boolean NOT NULL DEFAULT false,
    blocked_reason      text,
    failed_login_count  smallint NOT NULL DEFAULT 0,
    locked_until        timestamptz,
    last_login_at       timestamptz,
    timezone            text NOT NULL DEFAULT 'UTC',
    locale              text NOT NULL DEFAULT 'ru',
    theme               text NOT NULL DEFAULT 'system'
                        CHECK (theme IN ('light', 'dark', 'system')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);

COMMENT ON TABLE  users IS 'Пользователи сервиса';
COMMENT ON COLUMN users.email IS 'Email (citext — регистронезависимый)';
COMMENT ON COLUMN users.password_hash IS 'argon2id-хеш пароля';
COMMENT ON COLUMN users.email_verified_at IS 'Время подтверждения email; NULL — не подтверждён';
COMMENT ON COLUMN users.failed_login_count IS 'Счётчик неудачных попыток входа';
COMMENT ON COLUMN users.locked_until IS 'Время разблокировки после N неудач';
COMMENT ON COLUMN users.timezone IS 'IANA-таймзона пользователя';
COMMENT ON COLUMN users.deleted_at IS 'Soft-delete; NULL — активен';

CREATE UNIQUE INDEX ux_users_email_active
    ON users (email)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_users_created_at ON users (created_at);
CREATE INDEX ix_users_deleted_at ON users (deleted_at) WHERE deleted_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- email_verifications — коды подтверждения email
-- ---------------------------------------------------------------------------
CREATE TABLE email_verifications (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash   text NOT NULL,
    purpose     text NOT NULL DEFAULT 'email_verify'
                CHECK (purpose IN ('email_verify', 'password_reset', 'login_2fa')),
    expires_at  timestamptz NOT NULL,
    used_at     timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  email_verifications IS 'Коды подтверждения email / сброса пароля';
COMMENT ON COLUMN email_verifications.code_hash IS 'argon2-хеш 6-значного кода';
COMMENT ON COLUMN email_verifications.purpose IS 'Назначение кода';
COMMENT ON COLUMN email_verifications.expires_at IS 'TTL кода (15 минут)';

CREATE INDEX ix_email_verifications_user_purpose
    ON email_verifications (user_id, purpose, created_at DESC);
CREATE INDEX ix_email_verifications_expires_at
    ON email_verifications (expires_at);

-- ---------------------------------------------------------------------------
-- login_history — история входов (bigserial)
-- ---------------------------------------------------------------------------
CREATE TABLE login_history (
    id          bigserial PRIMARY KEY,
    user_id     uuid REFERENCES users(id) ON DELETE SET NULL,
    email       citext,
    ip          inet,
    user_agent  text,
    success     boolean NOT NULL,
    reason      text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  login_history IS 'История попыток входа';
COMMENT ON COLUMN login_history.user_id IS 'NULL, если пользователь не найден';
COMMENT ON COLUMN login_history.reason IS 'Причина неудачи (wrong_password, locked, etc.)';

CREATE INDEX ix_login_history_user_created
    ON login_history (user_id, created_at DESC);
CREATE INDEX ix_login_history_email_created
    ON login_history (email, created_at DESC);
CREATE INDEX ix_login_history_ip_created
    ON login_history (ip, created_at DESC);

-- ---------------------------------------------------------------------------
-- deleted_users — soft-delete дамп
-- ---------------------------------------------------------------------------
CREATE TABLE deleted_users (
    id              uuid PRIMARY KEY,
    email           citext NOT NULL,
    display_name    text,
    payload         jsonb NOT NULL,
    deleted_at      timestamptz NOT NULL DEFAULT now(),
    purge_after     timestamptz NOT NULL
);

COMMENT ON TABLE  deleted_users IS 'Архив удалённых пользователей (GDPR)';
COMMENT ON COLUMN deleted_users.payload IS 'Полный JSON-дамп данных пользователя';
COMMENT ON COLUMN deleted_users.purge_after IS 'Когда можно физически удалить';

CREATE INDEX ix_deleted_users_email ON deleted_users (email);
CREATE INDEX ix_deleted_users_purge_after ON deleted_users (purge_after);

-- ============================================================================
-- ЧАСТЬ 3. ЯЗЫКИ, КОЛОДЫ, КАРТОЧКИ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- language_groups — группы языков пользователя
-- ---------------------------------------------------------------------------
CREATE TABLE language_groups (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    language_code   char(2) NOT NULL REFERENCES languages(code) ON DELETE RESTRICT,
    title           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  language_groups IS 'Группы языков пользователя (напр. «Английский»)';
COMMENT ON COLUMN language_groups.title IS 'Пользовательское название; NULL — использовать name_ru из languages';

CREATE UNIQUE INDEX ux_language_groups_user_lang
    ON language_groups (user_id, language_code);
CREATE INDEX ix_language_groups_user ON language_groups (user_id);

-- ---------------------------------------------------------------------------
-- decks — колоды
-- ---------------------------------------------------------------------------
CREATE TABLE decks (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    language_group_id   uuid NOT NULL REFERENCES language_groups(id) ON DELETE CASCADE,
    source_lang         char(2) NOT NULL REFERENCES languages(code) ON DELETE RESTRICT,
    target_lang         char(2) NOT NULL REFERENCES languages(code) ON DELETE RESTRICT,
    title               text NOT NULL,
    description         text,
    position            integer NOT NULL DEFAULT 1,
    caret_position      integer NOT NULL DEFAULT 1,
    cards_count         integer NOT NULL DEFAULT 0,
    is_archived         boolean NOT NULL DEFAULT false,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    CONSTRAINT chk_decks_langs_differ CHECK (source_lang <> target_lang)
);

COMMENT ON TABLE  decks IS 'Колоды карточек';
COMMENT ON COLUMN decks.caret_position IS 'Позиция каретки для следующей карточки';
COMMENT ON COLUMN decks.cards_count IS 'Денормализованный счётчик карточек';
COMMENT ON COLUMN decks.deleted_at IS 'Soft-delete';

CREATE INDEX ix_decks_user ON decks (user_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_decks_language_group ON decks (language_group_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_decks_user_created ON decks (user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ux_decks_user_title_active
    ON decks (user_id, lower(title))
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- cards — карточки
-- ---------------------------------------------------------------------------
CREATE TABLE cards (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id         uuid NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    position        integer NOT NULL,
    status          text NOT NULL DEFAULT 'new'
                    CHECK (status IN ('new', 'learning', 'mastered')),
    bucket          smallint NOT NULL DEFAULT 1
                    CHECK (bucket BETWEEN 1 AND 6),
    front           text NOT NULL,
    translations    jsonb NOT NULL DEFAULT '[]'::jsonb,
    transcriptions  jsonb NOT NULL DEFAULT '[]'::jsonb,
    examples        jsonb NOT NULL DEFAULT '[]'::jsonb,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);

COMMENT ON TABLE  cards IS 'Карточки для изучения';
COMMENT ON COLUMN cards.position IS 'Порядок в колоде (1..N)';
COMMENT ON COLUMN cards.bucket IS 'Коробка Лейтнера: 1=День, 2=Неделя, 3=Месяц, 4=3 мес, 5=6 мес, 6=Год';
COMMENT ON COLUMN cards.front IS 'Лицевая сторона (слово/фраза)';
COMMENT ON COLUMN cards.translations IS 'JSON-массив переводов: [{"lang":"ru","text":"..."}]';
COMMENT ON COLUMN cards.transcriptions IS 'JSON-массив транскрипций (до 3): [{"type":"ipa","text":"..."}]';
COMMENT ON COLUMN cards.examples IS 'JSON-массив пар примеров: [{"source":"...","target":"..."}]';
COMMENT ON COLUMN cards.deleted_at IS 'Soft-delete';

CREATE UNIQUE INDEX ux_cards_deck_position
    ON cards (deck_id, position)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_cards_deck ON cards (deck_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_cards_user_status ON cards (user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX ix_cards_deck_status ON cards (deck_id, status) WHERE deleted_at IS NULL;
CREATE INDEX ix_cards_deck_bucket ON cards (deck_id, bucket) WHERE deleted_at IS NULL;
CREATE INDEX ix_cards_front_trgm ON cards USING gin (front gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- deleted_cards — архив удалённых карточек
-- ---------------------------------------------------------------------------
CREATE TABLE deleted_cards (
    id              uuid PRIMARY KEY,
    deck_id         uuid NOT NULL,
    user_id         uuid NOT NULL,
    payload         jsonb NOT NULL,
    stats_snapshot  jsonb NOT NULL DEFAULT '{}'::jsonb,
    deleted_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  deleted_cards IS 'Архив удалённых карточек с вычетом статистики';
COMMENT ON COLUMN deleted_cards.payload IS 'JSON-дамп карточки';
COMMENT ON COLUMN deleted_cards.stats_snapshot IS 'Снимок статистики на момент удаления';

CREATE INDEX ix_deleted_cards_user ON deleted_cards (user_id, deleted_at DESC);
CREATE INDEX ix_deleted_cards_deck ON deleted_cards (deck_id);

-- ============================================================================
-- ЧАСТЬ 4. СЕССИИ ОБУЧЕНИЯ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- learning_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE learning_sessions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    deck_id             uuid NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    bucket              smallint NOT NULL DEFAULT 1
                        CHECK (bucket BETWEEN 1 AND 6),
    direction           text NOT NULL DEFAULT 'source_to_target'
                        CHECK (direction IN ('source_to_target', 'target_to_source')),
    shuffled            boolean NOT NULL DEFAULT false,
    started_at          timestamptz NOT NULL DEFAULT now(),
    last_activity_at    timestamptz NOT NULL DEFAULT now(),
    ended_at            timestamptz,
    end_reason          text CHECK (end_reason IN ('manual', 'timeout')),
    cards_total         integer NOT NULL DEFAULT 0,
    cards_viewed        integer NOT NULL DEFAULT 0,
    cards_swiped_left   integer NOT NULL DEFAULT 0,
    cards_swiped_right  integer NOT NULL DEFAULT 0,
    duration_seconds    integer NOT NULL DEFAULT 0
);

COMMENT ON TABLE  learning_sessions IS 'Сессии обучения';
COMMENT ON COLUMN learning_sessions.direction IS 'Направление: source→target или target→source';
COMMENT ON COLUMN learning_sessions.end_reason IS 'manual — пользователь, timeout — 10 минут';
COMMENT ON COLUMN learning_sessions.duration_seconds IS 'Активное время сессии';

CREATE INDEX ix_learning_sessions_user ON learning_sessions (user_id, started_at DESC);
CREATE INDEX ix_learning_sessions_deck ON learning_sessions (deck_id, started_at DESC);
CREATE INDEX ix_learning_sessions_active
    ON learning_sessions (user_id, last_activity_at)
    WHERE ended_at IS NULL;

-- ---------------------------------------------------------------------------
-- card_stats — агрегированная статистика по карточке (per user per card)
-- ---------------------------------------------------------------------------
CREATE TABLE card_stats (
    card_id             uuid NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    views_count         integer NOT NULL DEFAULT 0,
    flips_count         integer NOT NULL DEFAULT 0,
    swipes_left         integer NOT NULL DEFAULT 0,
    swipes_right        integer NOT NULL DEFAULT 0,
    time_front_ms       bigint NOT NULL DEFAULT 0,
    time_back_ms        bigint NOT NULL DEFAULT 0,
    time_total_ms       bigint NOT NULL DEFAULT 0,
    sessions_count      integer NOT NULL DEFAULT 0,
    first_seen_at       timestamptz,
    last_seen_at        timestamptz,
    last_swipe_at       timestamptz,
    last_swipe_dir      text CHECK (last_swipe_dir IN ('left', 'right')),
    mastered_at         timestamptz,
    edits_count         integer NOT NULL DEFAULT 0,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (card_id, user_id)
);

COMMENT ON TABLE  card_stats IS 'Агрегированная статистика карточки (per card per user)';
COMMENT ON COLUMN card_stats.time_front_ms IS 'Суммарное время на лицевой стороне, мс';
COMMENT ON COLUMN card_stats.time_back_ms IS 'Суммарное время на обратной стороне, мс';
COMMENT ON COLUMN card_stats.last_swipe_dir IS 'Последнее направление свайпа (для revert)';
COMMENT ON COLUMN card_stats.edits_count IS 'Сколько раз карточку редактировали через PATCH /cards/:id';

CREATE INDEX ix_card_stats_user ON card_stats (user_id);
CREATE INDEX ix_card_stats_user_updated ON card_stats (user_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- deck_bucket_progress — прогресс по коробкам для колоды
-- ---------------------------------------------------------------------------
CREATE TABLE deck_bucket_progress (
    deck_id         uuid NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    bucket          smallint NOT NULL CHECK (bucket BETWEEN 1 AND 6),
    cards_count     integer NOT NULL DEFAULT 0,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (deck_id, bucket)
);

COMMENT ON TABLE  deck_bucket_progress IS 'Сколько карточек в каждой коробке колоды';

-- ---------------------------------------------------------------------------
-- bucket_stats — дневная статистика переходов между коробками
-- ---------------------------------------------------------------------------
CREATE TABLE bucket_stats (
    id              bigserial PRIMARY KEY,
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    deck_id         uuid NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    bucket          smallint NOT NULL CHECK (bucket BETWEEN 1 AND 6),
    day             date NOT NULL,
    inflow          integer NOT NULL DEFAULT 0,
    outflow         integer NOT NULL DEFAULT 0,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  bucket_stats IS 'Дневная статистика inflow/outflow по коробкам';
COMMENT ON COLUMN bucket_stats.inflow IS 'Сколько карточек пришло в коробку за день';
COMMENT ON COLUMN bucket_stats.outflow IS 'Сколько карточек ушло из коробки за день';

CREATE UNIQUE INDEX ux_bucket_stats_user_deck_bucket_day
    ON bucket_stats (user_id, deck_id, bucket, day);
CREATE INDEX ix_bucket_stats_deck_day ON bucket_stats (deck_id, day DESC);

-- ---------------------------------------------------------------------------
-- user_daily_stats — дневные агрегаты пользователя
-- ---------------------------------------------------------------------------
CREATE TABLE user_daily_stats (
    user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day                 date NOT NULL,
    cards_viewed        integer NOT NULL DEFAULT 0,
    cards_swiped_left   integer NOT NULL DEFAULT 0,
    cards_swiped_right  integer NOT NULL DEFAULT 0,
    sessions_count      integer NOT NULL DEFAULT 0,
    time_total_ms       bigint NOT NULL DEFAULT 0,
    cards_mastered      integer NOT NULL DEFAULT 0,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day)
);

COMMENT ON TABLE  user_daily_stats IS 'Дневные агрегаты пользователя (для streak и графиков)';

CREATE INDEX ix_user_daily_stats_day ON user_daily_stats (day DESC);

-- ============================================================================
-- ЧАСТЬ 5. ПАРТИЦИОНИРОВАННЫЕ ТАБЛИЦЫ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- card_session_history — история просмотров карточек в сессиях
-- Партиционирование по viewed_at (месяц)
-- ---------------------------------------------------------------------------
CREATE TABLE card_session_history (
    id              bigserial,
    session_id      uuid NOT NULL,
    card_id         uuid NOT NULL,
    user_id         uuid NOT NULL,
    deck_id         uuid NOT NULL,
    viewed_at       timestamptz NOT NULL DEFAULT now(),
    flipped         boolean NOT NULL DEFAULT false,
    flips_count     smallint NOT NULL DEFAULT 0,
    time_front_ms   integer NOT NULL DEFAULT 0,
    time_back_ms    integer NOT NULL DEFAULT 0,
    swipe_dir       text CHECK (swipe_dir IN ('left', 'right')),
    swiped_at       timestamptz,
    reverted        boolean NOT NULL DEFAULT false,
    reverted_at     timestamptz,
    PRIMARY KEY (id, viewed_at)
) PARTITION BY RANGE (viewed_at);

COMMENT ON TABLE  card_session_history IS 'История просмотров карточек (партиции по месяцам)';
COMMENT ON COLUMN card_session_history.reverted IS 'Был ли свайп отменён (revert)';

CREATE INDEX ix_csh_session ON card_session_history (session_id, viewed_at);
CREATE INDEX ix_csh_card ON card_session_history (card_id, viewed_at DESC);
CREATE INDEX ix_csh_user ON card_session_history (user_id, viewed_at DESC);
CREATE INDEX ix_csh_deck ON card_session_history (deck_id, viewed_at DESC);

-- ---------------------------------------------------------------------------
-- events — события (партиции по месяцам)
-- ---------------------------------------------------------------------------
CREATE TABLE events (
    id              bigserial,
    user_id         uuid,
    event_type      text NOT NULL,
    entity_type     text,
    entity_id       uuid,
    payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip              inet,
    user_agent      text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE  events IS 'События (аналитика, безопасность, аудит) — партиции по месяцам';
COMMENT ON COLUMN events.event_type IS 'Тип: session.started, card.swipe_reverted, auth.login_failed и т.д.';
COMMENT ON COLUMN events.entity_type IS 'Тип сущности: card, deck, session, user';
COMMENT ON COLUMN events.entity_id IS 'ID сущности';

CREATE INDEX ix_events_type_created ON events (event_type, created_at DESC);
CREATE INDEX ix_events_user_created ON events (user_id, created_at DESC);
CREATE INDEX ix_events_entity ON events (entity_type, entity_id, created_at DESC);
CREATE INDEX ix_events_payload_gin ON events USING gin (payload jsonb_path_ops);

-- ---------------------------------------------------------------------------
-- page_views — просмотры страниц (партиции по месяцам)
-- ---------------------------------------------------------------------------
CREATE TABLE page_views (
    id              bigserial,
    user_id         uuid,
    session_key     text,
    path            text NOT NULL,
    method          text NOT NULL DEFAULT 'GET',
    referer         text,
    ip              inet,
    user_agent      text,
    device_type     text,
    os              text,
    browser         text,
    country         char(2),
    city            text,
    duration_ms     integer,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE  page_views IS 'Просмотры страниц (рекламная аналитика) — партиции по месяцам';
COMMENT ON COLUMN page_views.session_key IS 'Анонимный ключ сессии (cookie)';
COMMENT ON COLUMN page_views.duration_ms IS 'Время на странице (заполняется асинхронно)';

CREATE INDEX ix_pv_created ON page_views (created_at DESC);
CREATE INDEX ix_pv_user_created ON page_views (user_id, created_at DESC);
CREATE INDEX ix_pv_path_created ON page_views (path, created_at DESC);
CREATE INDEX ix_pv_device_created ON page_views (device_type, created_at DESC);
CREATE INDEX ix_pv_country_created ON page_views (country, created_at DESC);

-- ============================================================================
-- ЧАСТЬ 6. АДМИНКА
-- ============================================================================

-- ---------------------------------------------------------------------------
-- admin_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE admin_sessions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token   text NOT NULL UNIQUE,
    ip              inet,
    user_agent      text,
    totp_verified   boolean NOT NULL DEFAULT false,
    expires_at      timestamptz NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  admin_sessions IS 'Сессии администраторов (короткий TTL)';

CREATE INDEX ix_admin_sessions_user ON admin_sessions (user_id);
CREATE INDEX ix_admin_sessions_expires ON admin_sessions (expires_at);

-- ---------------------------------------------------------------------------
-- admin_audit — аудит действий админов (bigserial)
-- ---------------------------------------------------------------------------
CREATE TABLE admin_audit (
    id              bigserial PRIMARY KEY,
    admin_id        uuid REFERENCES users(id) ON DELETE SET NULL,
    action          text NOT NULL,
    entity_type     text,
    entity_id       text,
    payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip              inet,
    created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  admin_audit IS 'Аудит действий администраторов';

CREATE INDEX ix_admin_audit_admin ON admin_audit (admin_id, created_at DESC);
CREATE INDEX ix_admin_audit_action ON admin_audit (action, created_at DESC);
CREATE INDEX ix_admin_audit_entity ON admin_audit (entity_type, entity_id);

-- ============================================================================
-- ЧАСТЬ 7. ФУНКЦИЯ АВТОСОЗДАНИЯ ПАРТИЦИЙ
-- ============================================================================

-- ---------------------------------------------------------------------------
-- create_monthly_partitions(parent_table, from_date)
-- Создаёт партицию на месяц, следующий за from_date.
-- Если from_date = NULL — берёт текущий месяц.
-- Возвращает имя созданной партиции.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_monthly_partition(
    p_parent_table text,
    p_from_date    date DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_base_date     date;
    v_start_date    date;
    v_end_date      date;
    v_partition     text;
    v_suffix        text;
    v_exists        boolean;
BEGIN
    -- Валидация имени таблицы (защита от SQL-инъекций)
    IF p_parent_table NOT IN ('events', 'page_views', 'card_session_history') THEN
        RAISE EXCEPTION 'Unknown parent table: %', p_parent_table;
    END IF;

    v_base_date := COALESCE(p_from_date, CURRENT_DATE);
    v_start_date := date_trunc('month', v_base_date)::date;
    v_end_date   := (v_start_date + interval '1 month')::date;
    v_suffix     := to_char(v_start_date, 'YYYY_MM');
    v_partition  := p_parent_table || '_' || v_suffix;

    SELECT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = v_partition
    ) INTO v_exists;

    IF v_exists THEN
        RETURN v_partition;
    END IF;

    EXECUTE format(
        'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
        v_partition, p_parent_table, v_start_date, v_end_date
    );

    RETURN v_partition;
END;
$$;

COMMENT ON FUNCTION create_monthly_partition(text, date)
    IS 'Создаёт месячную партицию для events/page_views/card_session_history. '
       'p_from_date — дата внутри месяца (по умолчанию — текущий месяц).';

-- ---------------------------------------------------------------------------
-- ensure_future_partitions(months_ahead)
-- Создаёт партиции на N месяцев вперёд для всех партиционированных таблиц.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ensure_future_partitions(p_months_ahead integer DEFAULT 2)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_table text;
    v_i     integer;
    v_date  date;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['events', 'page_views', 'card_session_history']
    LOOP
        FOR v_i IN 0..p_months_ahead LOOP
            v_date := (date_trunc('month', CURRENT_DATE) + (v_i || ' month')::interval)::date;
            PERFORM create_monthly_partition(v_table, v_date);
        END LOOP;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION ensure_future_partitions(integer)
    IS 'Создаёт партиции на N месяцев вперёд (по умолчанию 2) для всех партиционированных таблиц. '
       'Вызывать по cron раз в месяц.';

-- ---------------------------------------------------------------------------
-- Создаём стартовые партиции: текущий месяц + 2 вперёд
-- ---------------------------------------------------------------------------
SELECT ensure_future_partitions(2);

-- ============================================================================
-- ЧАСТЬ 8. ТРИГГЕРЫ updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION set_updated_at() IS 'Триггер: обновляет updated_at при UPDATE';

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users', 'language_groups', 'decks', 'cards',
        'card_stats', 'deck_bucket_progress', 'bucket_stats',
        'user_daily_stats'
    ]
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_updated_at
             BEFORE UPDATE ON %1$s
             FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
            t
        );
    END LOOP;
END;
$$;

-- ============================================================================
-- ЧАСТЬ 9. СПРАВОЧНИК ЯЗЫКОВ ISO 639-1
-- ============================================================================

INSERT INTO languages (code, code_alpha3, name_ru, name_en, native_name) VALUES
('aa','aar','Афарский','Afar','Afaraf'),
('ab','abk','Абхазский','Abkhaz','Аҧсуа'),
('ae','ave','Авестийский','Avestan','avesta'),
('af','afr','Африкаанс','Afrikaans','Afrikaans'),
('ak','aka','Акан','Akan','Akan'),
('am','amh','Амхарский','Amharic','አማርኛ'),
('an','arg','Арагонский','Aragonese','Aragonés'),
('ar','ara','Арабский','Arabic','العربية'),
('as','asm','Ассамский','Assamese','অসমীয়া'),
('av','ava','Аварский','Avaric','Авар'),
('ay','aym','Аймара','Aymara','Aymar aru'),
('az','aze','Азербайджанский','Azerbaijani','Azərbaycan'),
('ba','bak','Башкирский','Bashkir','Башҡортса'),
('be','bel','Белорусский','Belarusian','Беларуская'),
('bg','bul','Болгарский','Bulgarian','Български'),
('bh','bih','Бихарский','Bihari','भोजपुरी'),
('bi','bis','Бислама','Bislama','Bislama'),
('bm','bam','Бамбара','Bambara','Bamanankan'),
('bn','ben','Бенгальский','Bengali','বাংলা'),
('bo','bod','Тибетский','Tibetan','བོད་ཡིག'),
('br','bre','Бретонский','Breton','Brezhoneg'),
('bs','bos','Боснийский','Bosnian','Bosanski'),
('ca','cat','Каталанский','Catalan','Català'),
('ce','che','Чеченский','Chechen','Нохчийн'),
('ch','cha','Чаморро','Chamorro','Chamoru'),
('co','cos','Корсиканский','Corsican','Corsu'),
('cr','cre','Кри','Cree','ᓀᐦᐃᔭᐍᐏᐣ'),
('cs','ces','Чешский','Czech','Čeština'),
('cu','chu','Церковнославянский','Old Church Slavonic','Словѣньскъ'),
('cv','chv','Чувашский','Chuvash','Чӑвашла'),
('cy','cym','Валлийский','Welsh','Cymraeg'),
('da','dan','Датский','Danish','Dansk'),
('de','deu','Немецкий','German','Deutsch'),
('dv','div','Дивехи','Divehi','ދިވެހި'),
('dz','dzo','Дзонг-кэ','Dzongkha','རྫོང་ཁ'),
('ee','ewe','Эве','Ewe','Eʋegbe'),
('el','ell','Греческий','Greek','Ελληνικά'),
('en','eng','Английский','English','English'),
('eo','epo','Эсперанто','Esperanto','Esperanto'),
('es','spa','Испанский','Spanish','Español'),
('et','est','Эстонский','Estonian','Eesti'),
('eu','eus','Баскский','Basque','Euskara'),
('fa','fas','Персидский','Persian','فارسی'),
('ff','ful','Фула','Fulah','Fulfulde'),
('fi','fin','Финский','Finnish','Suomi'),
('fj','fij','Фиджийский','Fijian','Vosa Vakaviti'),
('fo','fao','Фарерский','Faroese','Føroyskt'),
('fr','fra','Французский','French','Français'),
('fy','fry','Западнофризский','Western Frisian','Frysk'),
('ga','gle','Ирландский','Irish','Gaeilge'),
('gd','gla','Шотландский гэльский','Scottish Gaelic','Gàidhlig'),
('gl','glg','Галисийский','Galician','Galego'),
('gn','grn','Гуарани','Guaraní','Avañe''ẽ'),
('gu','guj','Гуджарати','Gujarati','ગુજરાતી'),
('gv','glv','Мэнский','Manx','Gaelg'),
('ha','hau','Хауса','Hausa','Hausa'),
('he','heb','Иврит','Hebrew','עברית'),
('hi','hin','Хинди','Hindi','हिन्दी'),
('ho','hmo','Хири-моту','Hiri Motu','Hiri Motu'),
('hr','hrv','Хорватский','Croatian','Hrvatski'),
('ht','hat','Гаитянский','Haitian','Kreyòl ayisyen'),
('hu','hun','Венгерский','Hungarian','Magyar'),
('hy','hye','Армянский','Armenian','Հայերեն'),
('hz','her','Гереро','Herero','Otjiherero'),
('ia','ina','Интерлингва','Interlingua','Interlingua'),
('id','ind','Индонезийский','Indonesian','Bahasa Indonesia'),
('ie','ile','Интерлингве','Interlingue','Interlingue'),
('ig','ibo','Игбо','Igbo','Igbo'),
('ii','iii','Носу','Sichuan Yi','ꆈꌠꉙ'),
('ik','ipk','Инупиак','Inupiaq','Iñupiaq'),
('io','ido','Идо','Ido','Ido'),
('is','isl','Исландский','Icelandic','Íslenska'),
('it','ita','Итальянский','Italian','Italiano'),
('iu','iku','Инуктитут','Inuktitut','ᐃᓄᒃᑎᑐᑦ'),
('ja','jpn','Японский','Japanese','日本語'),
('jv','jav','Яванский','Javanese','Basa Jawa'),
('ka','kat','Грузинский','Georgian','ქართული'),
('kg','kon','Конго','Kongo','Kikongo'),
('ki','kik','Кикуйю','Kikuyu','Gĩkũyũ'),
('kj','kua','Кваньяма','Kuanyama','Kuanyama'),
('kk','kaz','Казахский','Kazakh','Қазақша'),
('kl','kal','Гренландский','Kalaallisut','Kalaallisut'),
('km','khm','Кхмерский','Khmer','ខ្មែរ'),
('kn','kan','Каннада','Kannada','ಕನ್ನಡ'),
('ko','kor','Корейский','Korean','한국어'),
('kr','kau','Канури','Kanuri','Kanuri'),
('ks','kas','Кашмири','Kashmiri','कॉशुर'),
('ku','kur','Курдский','Kurdish','Kurdî'),
('kv','kom','Коми','Komi','Коми'),
('kw','cor','Корнский','Cornish','Kernewek'),
('ky','kir','Киргизский','Kyrgyz','Кыргызча'),
('la','lat','Латинский','Latin','Latina'),
('lb','ltz','Люксембургский','Luxembourgish','Lëtzebuergesch'),
('lg','lug','Луганда','Ganda','Luganda'),
('li','lim','Лимбургский','Limburgish','Limburgs'),
('ln','lin','Лингала','Lingala','Lingála'),
('lo','lao','Лаосский','Lao','ລາວ'),
('lt','lit','Литовский','Lithuanian','Lietuvių'),
('lu','lub','Луба-катанга','Luba-Katanga','Kiluba'),
('lv','lav','Латышский','Latvian','Latviešu'),
('mg','mlg','Малагасийский','Malagasy','Malagasy'),
('mh','mah','Маршалльский','Marshallese','Kajin M̧ajeļ'),
('mi','mri','Маори','Māori','Te Reo Māori'),
('mk','mkd','Македонский','Macedonian','Македонски'),
('ml','mal','Малаялам','Malayalam','മലയാളം'),
('mn','mon','Монгольский','Mongolian','Монгол'),
('mr','mar','Маратхи','Marathi','मराठी'),
('ms','msa','Малайский','Malay','Bahasa Melayu'),
('mt','mlt','Мальтийский','Maltese','Malti'),
('my','mya','Бирманский','Burmese','မြန်မာ'),
('na','nau','Науру','Nauru','Dorerin Naoero'),
('nb','nob','Норвежский букмол','Norwegian Bokmål','Norsk bokmål'),
('nd','nde','Северный ндебеле','North Ndebele','isiNdebele'),
('ne','nep','Непальский','Nepali','नेपाली'),
('ng','ndo','Ндонга','Ndonga','Owambo'),
('nl','nld','Нидерландский','Dutch','Nederlands'),
('nn','nno','Норвежский нюношк','Norwegian Nynorsk','Norsk nynorsk'),
('no','nor','Норвежский','Norwegian','Norsk'),
('nr','nbl','Южный ндебеле','South Ndebele','isiNdebele'),
('nv','nav','Навахо','Navajo','Diné bizaad'),
('ny','nya','Чичева','Chichewa','ChiCheŵa'),
('oc','oci','Окситанский','Occitan','Occitan'),
('oj','oji','Оджибва','Ojibwe','ᐊᓂᔑᓈᐯᒧᐎᓐ'),
('om','orm','Оромо','Oromo','Oromoo'),
('or','ori','Ория','Oriya','ଓଡ଼ିଆ'),
('os','oss','Осетинский','Ossetian','Ирон'),
('pa','pan','Панджаби','Panjabi','ਪੰਜਾਬੀ'),
('pi','pli','Пали','Pali','पाऴि'),
('pl','pol','Польский','Polish','Polski'),
('ps','pus','Пушту','Pashto','پښتو'),
('pt','por','Португальский','Portuguese','Português'),
('qu','que','Кечуа','Quechua','Runa Simi'),
('rm','roh','Романшский','Romansh','Rumantsch'),
('rn','run','Кирунди','Rundi','Ikirundi'),
('ro','ron','Румынский','Romanian','Română'),
('ru','rus','Русский','Russian','Русский'),
('rw','kin','Киньяруанда','Kinyarwanda','Ikinyarwanda'),
('sa','san','Санскрит','Sanskrit','संस्कृतम्'),
('sc','srd','Сардинский','Sardinian','Sardu'),
('sd','snd','Синдхи','Sindhi','سنڌي'),
('se','sme','Северносаамский','Northern Sami','Davvisámegiella'),
('sg','sag','Санго','Sango','Sängö'),
('si','sin','Сингальский','Sinhala','සිංහල'),
('sk','slk','Словацкий','Slovak','Slovenčina'),
('sl','slv','Словенский','Slovenian','Slovenščina'),
('sm','smo','Самоанский','Samoan','Gagana Samoa'),
('sn','sna','Шона','Shona','ChiShona'),
('so','som','Сомалийский','Somali','Soomaaliga'),
('sq','sqi','Албанский','Albanian','Shqip'),
('sr','srp','Сербский','Serbian','Српски'),
('ss','ssw','Свази','Swati','SiSwati'),
('st','sot','Сесото','Southern Sotho','Sesotho'),
('su','sun','Сунданский','Sundanese','Basa Sunda'),
('sv','swe','Шведский','Swedish','Svenska'),
('sw','swa','Суахили','Swahili','Kiswahili'),
('ta','tam','Тамильский','Tamil','தமிழ்'),
('te','tel','Телугу','Telugu','తెలుగు'),
('tg','tgk','Таджикский','Tajik','Тоҷикӣ'),
('th','tha','Тайский','Thai','ไทย'),
('ti','tir','Тигринья','Tigrinya','ትግርኛ'),
('tk','tuk','Туркменский','Turkmen','Türkmençe'),
('tl','tgl','Тагальский','Tagalog','Tagalog'),
('tn','tsn','Тсвана','Tswana','Setswana'),
('to','ton','Тонганский','Tonga','Faka Tonga'),
('tr','tur','Турецкий','Turkish','Türkçe'),
('ts','tso','Тсонга','Tsonga','Xitsonga'),
('tt','tat','Татарский','Tatar','Татарча'),
('tw','twi','Тви','Twi','Twi'),
('ty','tah','Таитянский','Tahitian','Reo Tahiti'),
('ug','uig','Уйгурский','Uyghur','ئۇيغۇرچە'),
('uk','ukr','Украинский','Ukrainian','Українська'),
('ur','urd','Урду','Urdu','اردو'),
('uz','uzb','Узбекский','Uzbek','Oʻzbek'),
('ve','ven','Венда','Venda','Tshivenḓa'),
('vi','vie','Вьетнамский','Vietnamese','Tiếng Việt'),
('vo','vol','Волапюк','Volapük','Volapük'),
('wa','wln','Валлонский','Walloon','Walon'),
('wo','wol','Волоф','Wolof','Wolof'),
('xh','xho','Коса','Xhosa','isiXhosa'),
('yi','yid','Идиш','Yiddish','ייִדיש'),
('yo','yor','Йоруба','Yoruba','Yorùbá'),
('za','zha','Чжуанский','Zhuang','Vahcuengh'),
('zh','zho','Китайский','Chinese','中文'),
('zu','zul','Зулу','Zulu','isiZulu')
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- КОНЕЦ DDL
-- ============================================================================