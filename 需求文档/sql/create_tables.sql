-- ============================================================================
-- 本地音乐播放器 · 数据库建表语句
-- 关联文档：需求文档/07_数据库设计.md
-- 技术选型：SQLite（drift）　适用平台：iOS / Android / macOS / Windows / Linux
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 4.1 songs — 媒体库（音/视频统一）
-- ---------------------------------------------------------------------------
CREATE TABLE songs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT    NOT NULL,               -- 歌名（可编辑）
  artist          TEXT,                           -- 歌手
  album           TEXT,                           -- 专辑
  genre           TEXT,                           -- 流派（可编辑）
  duration_ms     INTEGER NOT NULL,               -- 时长（毫秒）
  media_type      INTEGER NOT NULL DEFAULT 0,     -- 0=音频 1=视频
  file_path       TEXT    NOT NULL UNIQUE,        -- 本地路径（防重复导入）
  cover_path      TEXT,                           -- 封面图路径
  is_favorite     INTEGER NOT NULL DEFAULT 0,     -- 0/1 喜欢
  play_count      INTEGER NOT NULL DEFAULT 0,     -- 播放次数
  last_played_at  INTEGER,                        -- 最近播放时间（epoch ms）
  created_at      INTEGER NOT NULL                -- 导入时间（epoch ms）
);

CREATE INDEX idx_songs_favorite  ON songs(is_favorite);
CREATE INDEX idx_songs_played    ON songs(last_played_at);
CREATE INDEX idx_songs_artist    ON songs(artist);
CREATE INDEX idx_songs_album     ON songs(album);
CREATE INDEX idx_songs_title     ON songs(title);
CREATE INDEX idx_songs_type      ON songs(media_type);

-- ---------------------------------------------------------------------------
-- 4.2 tags — 标签（含内置“来源:xxx”标签）
-- ---------------------------------------------------------------------------
CREATE TABLE tags (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT    NOT NULL UNIQUE,               -- 标签名
  color INTEGER NOT NULL DEFAULT 0             -- 标签色
);

-- ---------------------------------------------------------------------------
-- 4.3 songs_tags — 歌曲与标签关联（多对多）
-- ---------------------------------------------------------------------------
CREATE TABLE songs_tags (
  song_id INTEGER NOT NULL,
  tag_id  INTEGER NOT NULL,
  PRIMARY KEY (song_id, tag_id),
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id)  REFERENCES tags(id)  ON DELETE CASCADE
);

CREATE INDEX idx_songs_tags_tag ON songs_tags(tag_id);

-- ---------------------------------------------------------------------------
-- 4.4 queue_items — 当前播放队列（方案 B，逐行有序）
-- ---------------------------------------------------------------------------
CREATE TABLE queue_items (
  position INTEGER PRIMARY KEY,                -- 队列中的顺序
  song_id  INTEGER NOT NULL,
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------------
-- 4.5 lyrics_cache — 歌词缓存
-- ---------------------------------------------------------------------------
CREATE TABLE lyrics_cache (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  song_id  INTEGER NOT NULL UNIQUE,
  lrc_text TEXT    NOT NULL,
  FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
);
