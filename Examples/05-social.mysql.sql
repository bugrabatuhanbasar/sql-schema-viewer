-- =====================================================================
-- 05 · Medium · Social network
-- Dialect: MySQL 8+ (backticks, ENGINE trailer, AUTO_INCREMENT, JSON)
-- Tables:  ~30
-- Purpose: Exercises the MySQL parser path: quoted identifiers,
--          AUTO_INCREMENT, ENGINE=/CHARSET= trailers, table-level
--          CONSTRAINT/FOREIGN KEY blocks, ALTER TABLE ADD CONSTRAINT.
-- =====================================================================

CREATE TABLE `users` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `handle` VARCHAR(64) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `display_name` VARCHAR(120) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `avatar_url` VARCHAR(500),
  `bio` TEXT,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_handle_uq` (`handle`),
  UNIQUE KEY `users_email_uq`  (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `user_profiles` (
  `user_id` BIGINT UNSIGNED NOT NULL,
  `location` VARCHAR(120),
  `website`  VARCHAR(255),
  `birthday` DATE,
  `pronouns` VARCHAR(40),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_profile_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `user_settings` (
  `user_id` BIGINT UNSIGNED NOT NULL,
  `theme` VARCHAR(20) NOT NULL DEFAULT 'auto',
  `dm_from_strangers` TINYINT(1) NOT NULL DEFAULT 1,
  `notif_prefs` JSON,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_settings_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `user_sessions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `token_hash` CHAR(64) NOT NULL,
  `ip` VARBINARY(16),
  `user_agent` VARCHAR(255),
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_sessions_token_uq` (`token_hash`),
  KEY `user_sessions_user_idx` (`user_id`),
  CONSTRAINT `fk_session_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `follows` (
  `follower_id` BIGINT UNSIGNED NOT NULL,
  `followee_id` BIGINT UNSIGNED NOT NULL,
  `created_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`follower_id`, `followee_id`),
  CONSTRAINT `fk_follow_follower` FOREIGN KEY (`follower_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_follow_followee` FOREIGN KEY (`followee_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `blocks` (
  `blocker_id` BIGINT UNSIGNED NOT NULL,
  `blocked_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`blocker_id`, `blocked_id`),
  CONSTRAINT `fk_block_blocker` FOREIGN KEY (`blocker_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_block_blocked` FOREIGN KEY (`blocked_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `posts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `author_id` BIGINT UNSIGNED NOT NULL,
  `body` TEXT NOT NULL,
  `visibility` ENUM('public','followers','private') NOT NULL DEFAULT 'public',
  `reply_to_post_id` BIGINT UNSIGNED,
  `repost_of_post_id` BIGINT UNSIGNED,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `posts_author_idx` (`author_id`),
  KEY `posts_created_idx` (`created_at`),
  CONSTRAINT `fk_post_author` FOREIGN KEY (`author_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_post_reply` FOREIGN KEY (`reply_to_post_id`) REFERENCES `posts`(`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_post_repost` FOREIGN KEY (`repost_of_post_id`) REFERENCES `posts`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE `post_mentions` (
  `post_id` BIGINT UNSIGNED NOT NULL,
  `user_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`post_id`, `user_id`),
  CONSTRAINT `fk_mention_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_mention_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `hashtags` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `tag` VARCHAR(80) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `hashtags_tag_uq` (`tag`)
) ENGINE=InnoDB;

CREATE TABLE `post_hashtags` (
  `post_id` BIGINT UNSIGNED NOT NULL,
  `hashtag_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`post_id`, `hashtag_id`),
  CONSTRAINT `fk_ph_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ph_tag`  FOREIGN KEY (`hashtag_id`) REFERENCES `hashtags`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `post_media` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `kind` ENUM('image','video','gif') NOT NULL,
  `url` VARCHAR(500) NOT NULL,
  `alt` VARCHAR(255),
  `position` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `post_media_post_idx` (`post_id`),
  CONSTRAINT `fk_media_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `likes` (
  `user_id` BIGINT UNSIGNED NOT NULL,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `post_id`),
  CONSTRAINT `fk_like_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_like_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `bookmarks` (
  `user_id` BIGINT UNSIGNED NOT NULL,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `post_id`),
  CONSTRAINT `fk_bm_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_bm_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `direct_message_threads` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

CREATE TABLE `direct_message_participants` (
  `thread_id` BIGINT UNSIGNED NOT NULL,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `joined_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`thread_id`, `user_id`),
  CONSTRAINT `fk_dmp_thread` FOREIGN KEY (`thread_id`) REFERENCES `direct_message_threads`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_dmp_user`   FOREIGN KEY (`user_id`)   REFERENCES `users`(`id`)                  ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `direct_messages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `thread_id` BIGINT UNSIGNED NOT NULL,
  `sender_id` BIGINT UNSIGNED NOT NULL,
  `body` TEXT NOT NULL,
  `sent_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `read_at` DATETIME,
  PRIMARY KEY (`id`),
  KEY `dm_thread_idx` (`thread_id`),
  KEY `dm_sender_idx` (`sender_id`),
  CONSTRAINT `fk_dm_thread` FOREIGN KEY (`thread_id`) REFERENCES `direct_message_threads`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_dm_sender` FOREIGN KEY (`sender_id`) REFERENCES `users`(`id`)                  ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `lists` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_id` BIGINT UNSIGNED NOT NULL,
  `name` VARCHAR(120) NOT NULL,
  `is_public` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `lists_owner_idx` (`owner_id`),
  CONSTRAINT `fk_list_owner` FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `list_members` (
  `list_id` BIGINT UNSIGNED NOT NULL,
  `user_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`list_id`, `user_id`),
  CONSTRAINT `fk_lm_list` FOREIGN KEY (`list_id`) REFERENCES `lists`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_lm_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `polls` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `ends_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `polls_post_uq` (`post_id`),
  CONSTRAINT `fk_poll_post` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `poll_options` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `poll_id` BIGINT UNSIGNED NOT NULL,
  `label` VARCHAR(120) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `poll_options_poll_idx` (`poll_id`),
  CONSTRAINT `fk_option_poll` FOREIGN KEY (`poll_id`) REFERENCES `polls`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `poll_votes` (
  `poll_id` BIGINT UNSIGNED NOT NULL,
  `option_id` BIGINT UNSIGNED NOT NULL,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `voted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`poll_id`, `user_id`),
  CONSTRAINT `fk_vote_poll` FOREIGN KEY (`poll_id`) REFERENCES `polls`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_vote_option` FOREIGN KEY (`option_id`) REFERENCES `poll_options`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_vote_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `reports` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reporter_id` BIGINT UNSIGNED NOT NULL,
  `target_type` ENUM('user','post','comment','message') NOT NULL,
  `target_id` BIGINT UNSIGNED NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `status` ENUM('open','triaged','closed') NOT NULL DEFAULT 'open',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `reports_reporter_idx` (`reporter_id`),
  CONSTRAINT `fk_report_reporter` FOREIGN KEY (`reporter_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `moderation_actions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `moderator_id` BIGINT UNSIGNED NOT NULL,
  `subject_user_id` BIGINT UNSIGNED,
  `subject_post_id` BIGINT UNSIGNED,
  `action` VARCHAR(40) NOT NULL,
  `reason` TEXT,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `modact_mod_idx`  (`moderator_id`),
  KEY `modact_user_idx` (`subject_user_id`),
  KEY `modact_post_idx` (`subject_post_id`),
  CONSTRAINT `fk_modact_mod`  FOREIGN KEY (`moderator_id`)    REFERENCES `users`(`id`),
  CONSTRAINT `fk_modact_user` FOREIGN KEY (`subject_user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_modact_post` FOREIGN KEY (`subject_post_id`) REFERENCES `posts`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE `notifications` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `recipient_id` BIGINT UNSIGNED NOT NULL,
  `actor_id` BIGINT UNSIGNED,
  `kind` VARCHAR(40) NOT NULL,
  `subject_post_id` BIGINT UNSIGNED,
  `payload` JSON,
  `read_at` DATETIME,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `notif_recipient_idx` (`recipient_id`),
  KEY `notif_actor_idx` (`actor_id`),
  KEY `notif_post_idx` (`subject_post_id`),
  CONSTRAINT `fk_notif_recipient` FOREIGN KEY (`recipient_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_notif_actor`     FOREIGN KEY (`actor_id`)     REFERENCES `users`(`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_notif_post`      FOREIGN KEY (`subject_post_id`) REFERENCES `posts`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE `push_devices` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `platform` ENUM('ios','android','web') NOT NULL,
  `device_token` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `push_devices_token_uq` (`device_token`),
  KEY `push_devices_user_idx` (`user_id`),
  CONSTRAINT `fk_push_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `subscriptions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `tier` ENUM('free','pro','vip') NOT NULL DEFAULT 'free',
  `started_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` DATETIME,
  PRIMARY KEY (`id`),
  KEY `subs_user_idx` (`user_id`),
  CONSTRAINT `fk_sub_user` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `payments` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subscription_id` BIGINT UNSIGNED NOT NULL,
  `amount_cents` INT NOT NULL,
  `currency` CHAR(3) NOT NULL,
  `provider_ref` VARCHAR(120) NOT NULL,
  `paid_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `payments_provider_uq` (`provider_ref`),
  KEY `payments_sub_idx` (`subscription_id`),
  CONSTRAINT `fk_pay_sub` FOREIGN KEY (`subscription_id`) REFERENCES `subscriptions`(`id`)
) ENGINE=InnoDB;

CREATE TABLE `audit_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_user_id` BIGINT UNSIGNED,
  `entity` VARCHAR(60) NOT NULL,
  `entity_id` BIGINT UNSIGNED NOT NULL,
  `action` VARCHAR(40) NOT NULL,
  `payload` JSON,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `audit_actor_idx`  (`actor_user_id`),
  KEY `audit_entity_idx` (`entity`, `entity_id`),
  CONSTRAINT `fk_audit_actor` FOREIGN KEY (`actor_user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

-- A late-arriving constraint added via ALTER (exercises MySQL ALTER path).
ALTER TABLE `reports` ADD CONSTRAINT `fk_report_target_post`
  FOREIGN KEY (`target_id`) REFERENCES `posts`(`id`) ON DELETE CASCADE;
