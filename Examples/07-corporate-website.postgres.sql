-- =====================================================================
-- 07 · Small–Medium · Minimal corporate website
-- Dialect: PostgreSQL 15+
-- Tables:  ~18
-- Purpose: A realistic starter schema for a small B2B / consultancy /
--          agency corporate website. Public pages, a blog, services,
--          a team roster, careers, a lead-capture contact form, plus
--          a small admin backend (roles, media, audit log).
--
--          Nothing exotic — the FK graph mirrors what you'd inherit
--          when joining a real project's codebase on day one.
-- =====================================================================

BEGIN;

-- ===========================
--  1. AUTH & USERS (admin)
-- ===========================
--  Only staff members sign in. Public visitors browse anonymously.

CREATE TABLE roles (
  id           SMALLSERIAL PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,        -- 'admin' | 'editor' | 'author'
  display_name TEXT NOT NULL,
  description  TEXT
);

CREATE TABLE users (
  id            BIGSERIAL   PRIMARY KEY,
  role_id       SMALLINT    NOT NULL REFERENCES roles(id),
  email         TEXT        NOT NULL UNIQUE,
  password_hash TEXT        NOT NULL,
  full_name     TEXT        NOT NULL,
  avatar_url    TEXT,
  is_active     BOOLEAN     NOT NULL DEFAULT true,
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX users_role_id_idx ON users(role_id);

CREATE TABLE sessions (
  id           BIGSERIAL   PRIMARY KEY,
  user_id      BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT        NOT NULL UNIQUE,
  ip_address   INET,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX sessions_user_id_idx ON sessions(user_id);

-- ===========================
--  2. MEDIA LIBRARY
-- ===========================
--  Shared images / documents used across pages, blog, services, team.

CREATE TABLE media_assets (
  id           BIGSERIAL   PRIMARY KEY,
  uploader_id  BIGINT      REFERENCES users(id) ON DELETE SET NULL,
  kind         TEXT        NOT NULL CHECK (kind IN ('image','video','pdf','other')),
  file_name    TEXT        NOT NULL,
  storage_key  TEXT        NOT NULL UNIQUE,
  mime_type    TEXT        NOT NULL,
  bytes        BIGINT      NOT NULL,
  alt_text     TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX media_uploader_id_idx ON media_assets(uploader_id);

-- ===========================
--  3. PUBLIC PAGES (CMS)
-- ===========================
--  Home / About / Contact / custom pages, with a menu system.

CREATE TABLE pages (
  id             BIGSERIAL PRIMARY KEY,
  slug           TEXT NOT NULL UNIQUE,       -- '/', 'about', 'contact'
  title          TEXT NOT NULL,
  body_md        TEXT,
  hero_image_id  BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  meta_title     TEXT,
  meta_description TEXT,
  is_published   BOOLEAN NOT NULL DEFAULT false,
  published_at   TIMESTAMPTZ,
  author_id      BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX pages_author_id_idx     ON pages(author_id);
CREATE INDEX pages_hero_image_id_idx ON pages(hero_image_id);

CREATE TABLE menus (
  id       SERIAL PRIMARY KEY,
  slug     TEXT NOT NULL UNIQUE,             -- 'main', 'footer'
  name     TEXT NOT NULL
);

CREATE TABLE menu_items (
  id         SERIAL PRIMARY KEY,
  menu_id    INTEGER NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
  parent_id  INTEGER REFERENCES menu_items(id) ON DELETE CASCADE,
  page_id    BIGINT  REFERENCES pages(id)   ON DELETE SET NULL,
  label      TEXT    NOT NULL,
  external_url TEXT,
  position   INTEGER NOT NULL DEFAULT 0,
  CHECK (page_id IS NOT NULL OR external_url IS NOT NULL)
);
CREATE INDEX menu_items_menu_id_idx   ON menu_items(menu_id);
CREATE INDEX menu_items_parent_id_idx ON menu_items(parent_id);
CREATE INDEX menu_items_page_id_idx   ON menu_items(page_id);

-- ===========================
--  4. SERVICES
-- ===========================
--  What the company offers. One row per service card on /services.

CREATE TABLE services (
  id            BIGSERIAL PRIMARY KEY,
  slug          TEXT NOT NULL UNIQUE,
  title         TEXT NOT NULL,
  summary       TEXT,
  body_md       TEXT,
  icon_image_id BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  hero_image_id BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  position      INTEGER NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX services_icon_image_id_idx ON services(icon_image_id);
CREATE INDEX services_hero_image_id_idx ON services(hero_image_id);

-- ===========================
--  5. TEAM
-- ===========================
--  Public-facing "meet the team" section. Not the same as `users`
--  (users = admin logins).

CREATE TABLE team_members (
  id           BIGSERIAL PRIMARY KEY,
  full_name    TEXT NOT NULL,
  title        TEXT NOT NULL,
  bio_md       TEXT,
  photo_id     BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  email        TEXT,
  linkedin_url TEXT,
  position     INTEGER NOT NULL DEFAULT 0,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX team_members_photo_id_idx ON team_members(photo_id);

CREATE TABLE team_service_expertise (
  team_member_id BIGINT NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  service_id     BIGINT NOT NULL REFERENCES services(id)     ON DELETE CASCADE,
  PRIMARY KEY (team_member_id, service_id)
);

-- ===========================
--  6. BLOG / NEWS
-- ===========================

CREATE TABLE categories (
  id    SERIAL PRIMARY KEY,
  slug  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE tags (
  id    SERIAL PRIMARY KEY,
  slug  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE posts (
  id             BIGSERIAL PRIMARY KEY,
  author_id      BIGINT      NOT NULL REFERENCES users(id),
  category_id    INTEGER     REFERENCES categories(id) ON DELETE SET NULL,
  cover_image_id BIGINT      REFERENCES media_assets(id) ON DELETE SET NULL,
  slug           TEXT        NOT NULL UNIQUE,
  title          TEXT        NOT NULL,
  excerpt        TEXT,
  body_md        TEXT        NOT NULL,
  status         TEXT        NOT NULL CHECK (status IN ('draft','scheduled','published','archived')),
  published_at   TIMESTAMPTZ,
  meta_title     TEXT,
  meta_description TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX posts_author_id_idx       ON posts(author_id);
CREATE INDEX posts_category_id_idx     ON posts(category_id);
CREATE INDEX posts_cover_image_id_idx  ON posts(cover_image_id);
CREATE INDEX posts_status_idx          ON posts(status);
CREATE INDEX posts_published_at_idx    ON posts(published_at);

CREATE TABLE post_tags (
  post_id BIGINT  NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);

-- ===========================
--  7. TESTIMONIALS
-- ===========================
--  Customer quotes for /home and /services pages.

CREATE TABLE testimonials (
  id            BIGSERIAL PRIMARY KEY,
  author_name   TEXT NOT NULL,
  author_title  TEXT,               -- 'CTO, Acme Inc.'
  quote         TEXT NOT NULL,
  photo_id      BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  service_id    BIGINT REFERENCES services(id)    ON DELETE SET NULL, -- optional: which service the quote endorses
  is_featured   BOOLEAN NOT NULL DEFAULT false,
  position      INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX testimonials_service_id_idx ON testimonials(service_id);
CREATE INDEX testimonials_photo_id_idx   ON testimonials(photo_id);

-- ===========================
--  8. CAREERS
-- ===========================

CREATE TABLE job_openings (
  id           BIGSERIAL PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,
  title        TEXT NOT NULL,
  location     TEXT,
  employment_type TEXT CHECK (employment_type IN ('full_time','part_time','contract','intern')),
  description_md TEXT NOT NULL,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  posted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  closes_at    TIMESTAMPTZ
);

CREATE TABLE job_applications (
  id                BIGSERIAL PRIMARY KEY,
  job_id            BIGINT NOT NULL REFERENCES job_openings(id) ON DELETE CASCADE,
  applicant_name    TEXT   NOT NULL,
  applicant_email   TEXT   NOT NULL,
  applicant_phone   TEXT,
  cover_letter      TEXT,
  cv_media_id       BIGINT REFERENCES media_assets(id) ON DELETE SET NULL,
  status            TEXT   NOT NULL DEFAULT 'new' CHECK (status IN ('new','in_review','interview','offer','rejected','hired')),
  submitted_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX job_applications_job_id_idx      ON job_applications(job_id);
CREATE INDEX job_applications_cv_media_id_idx ON job_applications(cv_media_id);
CREATE INDEX job_applications_status_idx      ON job_applications(status);

-- ===========================
--  9. CONTACT / LEADS
-- ===========================

CREATE TABLE contact_messages (
  id           BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL,
  email        TEXT NOT NULL,
  phone        TEXT,
  company      TEXT,
  subject      TEXT,
  message      TEXT NOT NULL,
  service_id   BIGINT REFERENCES services(id) ON DELETE SET NULL,  -- optional interest
  handled_by   BIGINT REFERENCES users(id)    ON DELETE SET NULL,
  status       TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','responded','closed','spam')),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ
);
CREATE INDEX contact_messages_service_id_idx ON contact_messages(service_id);
CREATE INDEX contact_messages_handled_by_idx ON contact_messages(handled_by);
CREATE INDEX contact_messages_status_idx     ON contact_messages(status);

CREATE TABLE newsletter_subscribers (
  id             BIGSERIAL PRIMARY KEY,
  email          TEXT NOT NULL UNIQUE,
  confirmed_at   TIMESTAMPTZ,
  unsubscribed_at TIMESTAMPTZ,
  source_page_id BIGINT REFERENCES pages(id) ON DELETE SET NULL,   -- where they opted in
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX newsletter_subscribers_source_page_id_idx
  ON newsletter_subscribers(source_page_id);

-- ===========================
--  10. AUDIT LOG (admin)
-- ===========================

CREATE TABLE audit_log (
  id           BIGSERIAL PRIMARY KEY,
  actor_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  entity       TEXT NOT NULL,        -- 'posts','pages','services',...
  entity_id    BIGINT NOT NULL,
  action       TEXT NOT NULL,        -- 'create','update','delete','publish'
  before       JSONB,
  after        JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_actor_id_idx ON audit_log(actor_id);
CREATE INDEX audit_log_entity_idx   ON audit_log(entity, entity_id);

COMMIT;
