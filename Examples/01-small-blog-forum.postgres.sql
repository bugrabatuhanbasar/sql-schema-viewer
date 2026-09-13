-- =====================================================================
-- 01 · Small · Blog + Forum
-- Dialect: PostgreSQL 15+
-- Tables:  ~20
-- Purpose: Newcomer-friendly schema. Two loosely connected domains
--          (blogging + threaded discussion) that share a single user
--          table.
-- =====================================================================

BEGIN;

-- users & auth ---------------------------------------------------------

CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  username      TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  avatar_url    TEXT,
  bio           TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMPTZ
);
CREATE INDEX users_username_idx ON users(username);

CREATE TABLE user_sessions (
  id           BIGSERIAL PRIMARY KEY,
  user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT   NOT NULL UNIQUE,
  ip_address   INET,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX user_sessions_user_id_idx ON user_sessions(user_id);

CREATE TABLE user_followers (
  follower_id  BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id  BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

-- blog -----------------------------------------------------------------

CREATE TABLE blogs (
  id          BIGSERIAL PRIMARY KEY,
  owner_id    BIGINT NOT NULL REFERENCES users(id),
  slug        TEXT   NOT NULL UNIQUE,
  title       TEXT   NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX blogs_owner_id_idx ON blogs(owner_id);

CREATE TABLE posts (
  id           BIGSERIAL PRIMARY KEY,
  blog_id      BIGINT NOT NULL REFERENCES blogs(id) ON DELETE CASCADE,
  author_id    BIGINT NOT NULL REFERENCES users(id),
  slug         TEXT   NOT NULL,
  title        TEXT   NOT NULL,
  body_md      TEXT   NOT NULL,
  status       TEXT   NOT NULL CHECK (status IN ('draft','published','archived')),
  published_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (blog_id, slug)
);
CREATE INDEX posts_blog_id_idx      ON posts(blog_id);
CREATE INDEX posts_author_id_idx    ON posts(author_id);
CREATE INDEX posts_published_at_idx ON posts(published_at);

CREATE TABLE tags (
  id    BIGSERIAL PRIMARY KEY,
  slug  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE post_tags (
  post_id BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  tag_id  BIGINT NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);

CREATE TABLE post_reactions (
  id         BIGSERIAL PRIMARY KEY,
  post_id    BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reaction   TEXT   NOT NULL CHECK (reaction IN ('like','love','clap','fire')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id, reaction)
);
CREATE INDEX post_reactions_post_id_idx ON post_reactions(post_id);

CREATE TABLE post_comments (
  id           BIGSERIAL PRIMARY KEY,
  post_id      BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id    BIGINT NOT NULL REFERENCES users(id),
  parent_id    BIGINT REFERENCES post_comments(id) ON DELETE CASCADE,
  body_md      TEXT   NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at    TIMESTAMPTZ
);
CREATE INDEX post_comments_post_id_idx   ON post_comments(post_id);
CREATE INDEX post_comments_author_id_idx ON post_comments(author_id);
CREATE INDEX post_comments_parent_id_idx ON post_comments(parent_id);

CREATE TABLE media_assets (
  id          BIGSERIAL PRIMARY KEY,
  owner_id    BIGINT NOT NULL REFERENCES users(id),
  kind        TEXT   NOT NULL CHECK (kind IN ('image','video','audio','file')),
  storage_key TEXT   NOT NULL UNIQUE,
  mime_type   TEXT   NOT NULL,
  bytes       BIGINT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX media_assets_owner_id_idx ON media_assets(owner_id);

CREATE TABLE post_media (
  post_id  BIGINT NOT NULL REFERENCES posts(id)        ON DELETE CASCADE,
  media_id BIGINT NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
  position INT    NOT NULL DEFAULT 0,
  PRIMARY KEY (post_id, media_id)
);

-- forum ----------------------------------------------------------------

CREATE TABLE forums (
  id          BIGSERIAL PRIMARY KEY,
  slug        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE forum_moderators (
  forum_id BIGINT NOT NULL REFERENCES forums(id) ON DELETE CASCADE,
  user_id  BIGINT NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (forum_id, user_id)
);

CREATE TABLE threads (
  id           BIGSERIAL PRIMARY KEY,
  forum_id     BIGINT NOT NULL REFERENCES forums(id) ON DELETE CASCADE,
  author_id    BIGINT NOT NULL REFERENCES users(id),
  title        TEXT   NOT NULL,
  is_pinned    BOOLEAN NOT NULL DEFAULT false,
  is_locked    BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_post_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX threads_forum_id_idx     ON threads(forum_id);
CREATE INDEX threads_author_id_idx    ON threads(author_id);
CREATE INDEX threads_last_post_at_idx ON threads(last_post_at);

CREATE TABLE thread_posts (
  id         BIGSERIAL PRIMARY KEY,
  thread_id  BIGINT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
  author_id  BIGINT NOT NULL REFERENCES users(id),
  body_md    TEXT   NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at  TIMESTAMPTZ
);
CREATE INDEX thread_posts_thread_id_idx ON thread_posts(thread_id);
CREATE INDEX thread_posts_author_id_idx ON thread_posts(author_id);

CREATE TABLE thread_post_reactions (
  id             BIGSERIAL PRIMARY KEY,
  thread_post_id BIGINT NOT NULL REFERENCES thread_posts(id) ON DELETE CASCADE,
  user_id        BIGINT NOT NULL REFERENCES users(id)        ON DELETE CASCADE,
  reaction       TEXT   NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (thread_post_id, user_id, reaction)
);

-- notifications & audit -----------------------------------------------

CREATE TABLE notifications (
  id           BIGSERIAL PRIMARY KEY,
  recipient_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id     BIGINT REFERENCES users(id),
  kind         TEXT   NOT NULL,
  payload      JSONB  NOT NULL DEFAULT '{}'::jsonb,
  read_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX notifications_recipient_id_idx ON notifications(recipient_id);
CREATE INDEX notifications_actor_id_idx     ON notifications(actor_id);

CREATE TABLE audit_events (
  id         BIGSERIAL PRIMARY KEY,
  actor_id   BIGINT REFERENCES users(id),
  entity     TEXT   NOT NULL,
  entity_id  BIGINT NOT NULL,
  action     TEXT   NOT NULL,
  payload    JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_actor_id_idx ON audit_events(actor_id);
CREATE INDEX audit_events_entity_idx   ON audit_events(entity, entity_id);

COMMIT;
