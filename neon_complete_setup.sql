-- ============================================
-- COMPLETE NEON DATABASE SETUP
-- ============================================
-- This file creates all tables, functions, triggers, and indexes

-- ============================================
-- 1. CREATE TABLES
-- ============================================

-- Users table (custom auth system)
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  password_hash TEXT,
  password_salt TEXT,
  verification_token TEXT,
  email_verified BOOLEAN DEFAULT FALSE,
  two_factor_enabled BOOLEAN DEFAULT FALSE,
  avatar_url TEXT,
  cover_url TEXT,
  reset_token TEXT,
  reset_token_expiry TIMESTAMP,
  role TEXT DEFAULT 'user',
  is_active BOOLEAN DEFAULT TRUE,
  gitu_enabled BOOLEAN DEFAULT FALSE,
  gitu_settings JSON,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Notebooks table
CREATE TABLE IF NOT EXISTS notebooks (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Sources table (with media storage)
CREATE TABLE IF NOT EXISTS sources (
  id TEXT PRIMARY KEY,
  notebook_id TEXT NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  type TEXT NOT NULL, -- 'url', 'file', 'youtube', 'drive', 'text', 'audio', 'image', 'video'
  content TEXT,
  url TEXT,
  media_data BYTEA, -- Binary data for images, videos, audio
  summary TEXT,
  summary_generated_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Tags table
CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#3B82F6',
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, name)
);

-- Source-Tag junction table
CREATE TABLE IF NOT EXISTS source_tags (
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (source_id, tag_id)
);

-- Shares table (for notebook sharing)
CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  notebook_id TEXT NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
  token TEXT UNIQUE NOT NULL,
  access_level TEXT DEFAULT 'read', -- 'read', 'write'
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- 2. ANALYTICS FUNCTIONS
-- ============================================

-- Get user statistics
CREATE OR REPLACE FUNCTION get_user_stats(user_id_param TEXT)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_notebooks', (SELECT COUNT(*) FROM notebooks WHERE user_id = user_id_param),
    'total_sources', (SELECT COUNT(*) FROM sources s 
                      JOIN notebooks n ON s.notebook_id = n.id 
                      WHERE n.user_id = user_id_param),
    'total_tags', (SELECT COUNT(DISTINCT tag_id) FROM source_tags st
                   JOIN sources s ON st.source_id = s.id
                   JOIN notebooks n ON s.notebook_id = n.id
                   WHERE n.user_id = user_id_param),
    'sources_by_type', (SELECT json_object_agg(type, count)
                        FROM (SELECT s.type, COUNT(*) as count
                              FROM sources s
                              JOIN notebooks n ON s.notebook_id = n.id
                              WHERE n.user_id = user_id_param
                              GROUP BY s.type) sub),
    'recent_activity', (SELECT COUNT(*) FROM sources s
                        JOIN notebooks n ON s.notebook_id = n.id
                        WHERE n.user_id = user_id_param
                        AND s.created_at > NOW() - INTERVAL '7 days')
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Get notebook analytics
CREATE OR REPLACE FUNCTION get_notebook_analytics(notebook_id_param TEXT)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'source_count', (SELECT COUNT(*) FROM sources WHERE notebook_id = notebook_id_param),
    'total_content_size', (SELECT COALESCE(SUM(LENGTH(content)), 0) FROM sources WHERE notebook_id = notebook_id_param),
    'sources_by_type', (SELECT json_object_agg(type, count)
                        FROM (SELECT type, COUNT(*) as count
                              FROM sources
                              WHERE notebook_id = notebook_id_param
                              GROUP BY type) sub),
    'tag_count', (SELECT COUNT(DISTINCT tag_id) FROM source_tags st
                  JOIN sources s ON st.source_id = s.id
                  WHERE s.notebook_id = notebook_id_param),
    'last_updated', (SELECT MAX(created_at) FROM sources WHERE notebook_id = notebook_id_param)
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 3. SEARCH FUNCTIONS
-- ============================================

-- Full-text search across sources
CREATE OR REPLACE FUNCTION search_sources(
  user_id_param TEXT,
  search_query TEXT,
  limit_param INTEGER DEFAULT 20
)
RETURNS TABLE(
  id TEXT,
  title TEXT,
  type TEXT,
  content TEXT,
  notebook_id TEXT,
  created_at TIMESTAMP,
  rank REAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.id,
    s.title,
    s.type,
    LEFT(s.content, 500) as content,
    s.notebook_id,
    s.created_at,
    ts_rank(
      to_tsvector('english', COALESCE(s.title, '') || ' ' || COALESCE(s.content, '')),
      plainto_tsquery('english', search_query)
    ) as rank
  FROM sources s
  JOIN notebooks n ON s.notebook_id = n.id
  WHERE n.user_id = user_id_param
    AND (
      to_tsvector('english', COALESCE(s.title, '') || ' ' || COALESCE(s.content, ''))
      @@ plainto_tsquery('english', search_query)
    )
  ORDER BY rank DESC
  LIMIT limit_param;
END;
$$ LANGUAGE plpgsql;

-- Search with filters
CREATE OR REPLACE FUNCTION search_sources_filtered(
  user_id_param TEXT,
  search_query TEXT,
  source_type TEXT DEFAULT NULL,
  tag_ids TEXT[] DEFAULT NULL,
  limit_param INTEGER DEFAULT 20
)
RETURNS TABLE(
  id TEXT,
  title TEXT,
  type TEXT,
  content TEXT,
  notebook_id TEXT,
  created_at TIMESTAMP
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    s.id,
    s.title,
    s.type,
    LEFT(s.content, 500) as content,
    s.notebook_id,
    s.created_at
  FROM sources s
  JOIN notebooks n ON s.notebook_id = n.id
  LEFT JOIN source_tags st ON s.id = st.source_id
  WHERE n.user_id = user_id_param
    AND (search_query IS NULL OR search_query = '' OR
         s.title ILIKE '%' || search_query || '%' OR
         s.content ILIKE '%' || search_query || '%')
    AND (source_type IS NULL OR s.type = source_type)
    AND (tag_ids IS NULL OR st.tag_id = ANY(tag_ids))
  ORDER BY s.created_at DESC
  LIMIT limit_param;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. TAG MANAGEMENT FUNCTIONS
-- ============================================

-- Get or create tag
CREATE OR REPLACE FUNCTION get_or_create_tag(
  user_id_param TEXT,
  tag_name_param TEXT,
  tag_color_param TEXT DEFAULT '#3B82F6'
)
RETURNS TEXT AS $$
DECLARE
  tag_id_result TEXT;
BEGIN
  SELECT id INTO tag_id_result
  FROM tags
  WHERE user_id = user_id_param AND name = tag_name_param;
  
  IF tag_id_result IS NULL THEN
    INSERT INTO tags (id, user_id, name, color, created_at)
    VALUES (gen_random_uuid()::TEXT, user_id_param, tag_name_param, tag_color_param, NOW())
    RETURNING id INTO tag_id_result;
  END IF;
  
  RETURN tag_id_result;
END;
$$ LANGUAGE plpgsql;

-- Add tag to source
CREATE OR REPLACE FUNCTION add_tag_to_source(
  source_id_param TEXT,
  tag_id_param TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
  INSERT INTO source_tags (source_id, tag_id)
  VALUES (source_id_param, tag_id_param)
  ON CONFLICT (source_id, tag_id) DO NOTHING;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Remove tag from source
CREATE OR REPLACE FUNCTION remove_tag_from_source(
  source_id_param TEXT,
  tag_id_param TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
  DELETE FROM source_tags
  WHERE source_id = source_id_param AND tag_id = tag_id_param;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Get popular tags for user
CREATE OR REPLACE FUNCTION get_popular_tags(
  user_id_param TEXT,
  limit_param INTEGER DEFAULT 10
)
RETURNS TABLE(
  id TEXT,
  name TEXT,
  color TEXT,
  usage_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id,
    t.name,
    t.color,
    COUNT(st.source_id) as usage_count
  FROM tags t
  LEFT JOIN source_tags st ON t.id = st.tag_id
  WHERE t.user_id = user_id_param
  GROUP BY t.id, t.name, t.color
  ORDER BY usage_count DESC
  LIMIT limit_param;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. BULK OPERATIONS
-- ============================================

-- Bulk delete sources
CREATE OR REPLACE FUNCTION bulk_delete_sources(
  source_ids_param TEXT[]
)
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM sources
  WHERE id = ANY(source_ids_param);
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Bulk add tags to sources
CREATE OR REPLACE FUNCTION bulk_add_tags(
  source_ids_param TEXT[],
  tag_ids_param TEXT[]
)
RETURNS INTEGER AS $$
DECLARE
  inserted_count INTEGER := 0;
  source_id_var TEXT;
  tag_id_var TEXT;
BEGIN
  FOREACH source_id_var IN ARRAY source_ids_param
  LOOP
    FOREACH tag_id_var IN ARRAY tag_ids_param
    LOOP
      INSERT INTO source_tags (source_id, tag_id)
      VALUES (source_id_var, tag_id_var)
      ON CONFLICT (source_id, tag_id) DO NOTHING;
      
      IF FOUND THEN
        inserted_count := inserted_count + 1;
      END IF;
    END LOOP;
  END LOOP;
  
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql;

-- Bulk remove tags from sources
CREATE OR REPLACE FUNCTION bulk_remove_tags(
  source_ids_param TEXT[],
  tag_ids_param TEXT[]
)
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER := 0;
  source_id_var TEXT;
  tag_id_var TEXT;
BEGIN
  FOREACH source_id_var IN ARRAY source_ids_param
  LOOP
    FOREACH tag_id_var IN ARRAY tag_ids_param
    LOOP
      DELETE FROM source_tags
      WHERE source_id = source_id_var
        AND tag_id = tag_id_var;
      
      IF FOUND THEN
        deleted_count := deleted_count + 1;
      END IF;
    END LOOP;
  END LOOP;
  
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Bulk move sources to notebook
CREATE OR REPLACE FUNCTION bulk_move_sources(
  source_ids_param TEXT[],
  target_notebook_id TEXT
)
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE sources
  SET notebook_id = target_notebook_id
  WHERE id = ANY(source_ids_param);
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 6. MEDIA MANAGEMENT FUNCTIONS
-- ============================================

-- Get media size for user
CREATE OR REPLACE FUNCTION get_user_media_size(user_id_param TEXT)
RETURNS BIGINT AS $$
DECLARE
  total_size BIGINT;
BEGIN
  SELECT COALESCE(SUM(OCTET_LENGTH(s.media_data)), 0) INTO total_size
  FROM sources s
  JOIN notebooks n ON s.notebook_id = n.id
  WHERE n.user_id = user_id_param
    AND s.media_data IS NOT NULL;
  
  RETURN total_size;
END;
$$ LANGUAGE plpgsql;

-- Clean up orphaned media
CREATE OR REPLACE FUNCTION cleanup_orphaned_media()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM sources
  WHERE notebook_id NOT IN (SELECT id FROM notebooks);
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 7. SHARING FUNCTIONS
-- ============================================

-- Create share token for notebook
CREATE OR REPLACE FUNCTION create_share_token(
  notebook_id_param TEXT,
  access_level_param TEXT DEFAULT 'read',
  expires_in_days INTEGER DEFAULT 7
)
RETURNS JSON AS $$
DECLARE
  token TEXT;
  expires_at TIMESTAMP;
  result JSON;
BEGIN
  token := encode(gen_random_bytes(32), 'base64');
  expires_at := NOW() + (expires_in_days || ' days')::INTERVAL;
  
  INSERT INTO shares (id, notebook_id, token, access_level, expires_at, created_at)
  VALUES (gen_random_uuid()::TEXT, notebook_id_param, token, access_level_param, expires_at, NOW())
  RETURNING json_build_object(
    'token', token,
    'expires_at', expires_at,
    'access_level', access_level_param
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Validate share token
CREATE OR REPLACE FUNCTION validate_share_token(token_param TEXT)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'valid', TRUE,
    'notebook_id', notebook_id,
    'access_level', access_level
  ) INTO result
  FROM shares
  WHERE token = token_param
    AND (expires_at IS NULL OR expires_at > NOW());
  
  IF result IS NULL THEN
    result := json_build_object('valid', FALSE);
  END IF;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- List all shares for a notebook
CREATE OR REPLACE FUNCTION list_shares(notebook_id_param TEXT)
RETURNS TABLE(
  id TEXT,
  token TEXT,
  access_level TEXT,
  expires_at TIMESTAMP,
  created_at TIMESTAMP
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.id,
    s.token,
    s.access_level,
    s.expires_at,
    s.created_at
  FROM shares s
  WHERE s.notebook_id = notebook_id_param
    AND (s.expires_at IS NULL OR s.expires_at > NOW())
  ORDER BY s.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Revoke a share token
CREATE OR REPLACE FUNCTION revoke_share(
  notebook_id_param TEXT,
  token_param TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM shares
  WHERE notebook_id = notebook_id_param
    AND token = token_param;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count > 0;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 8. RECOMMENDATION FUNCTIONS
-- ============================================

-- Get related sources based on content similarity
CREATE OR REPLACE FUNCTION get_related_sources(
  source_id_param TEXT,
  limit_param INTEGER DEFAULT 5
)
RETURNS TABLE(
  id TEXT,
  title TEXT,
  type TEXT,
  similarity REAL
) AS $$
BEGIN
  RETURN QUERY
  WITH source_vector AS (
    SELECT to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(content, '')) as vec
    FROM sources
    WHERE id = source_id_param
  )
  SELECT 
    s.id,
    s.title,
    s.type,
    ts_rank(
      to_tsvector('english', COALESCE(s.title, '') || ' ' || COALESCE(s.content, '')),
      (SELECT vec FROM source_vector)
    ) as similarity
  FROM sources s
  WHERE s.id != source_id_param
    AND s.notebook_id = (SELECT notebook_id FROM sources WHERE id = source_id_param)
  ORDER BY similarity DESC
  LIMIT limit_param;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 9. TRIGGERS FOR AUTOMATION
-- ============================================

-- Auto-update notebook timestamp when sources change
CREATE OR REPLACE FUNCTION update_notebook_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE notebooks
  SET updated_at = NOW()
  WHERE id = COALESCE(NEW.notebook_id, OLD.notebook_id);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS source_update_notebook_trigger ON sources;
CREATE TRIGGER source_update_notebook_trigger
AFTER INSERT OR UPDATE OR DELETE ON sources
FOR EACH ROW
EXECUTE FUNCTION update_notebook_timestamp();

-- Auto-delete orphaned tags
CREATE OR REPLACE FUNCTION cleanup_unused_tags()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM tags
  WHERE id NOT IN (SELECT DISTINCT tag_id FROM source_tags)
    AND created_at < NOW() - INTERVAL '30 days';
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS cleanup_tags_trigger ON source_tags;
CREATE TRIGGER cleanup_tags_trigger
AFTER DELETE ON source_tags
FOR EACH STATEMENT
EXECUTE FUNCTION cleanup_unused_tags();

-- ============================================
-- 10. INDEXES FOR PERFORMANCE
-- ============================================

-- Full-text search indexes
CREATE INDEX IF NOT EXISTS idx_sources_fts ON sources 
USING GIN (to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(content, '')));

-- Common query indexes
CREATE INDEX IF NOT EXISTS idx_sources_notebook_id ON sources(notebook_id);
CREATE INDEX IF NOT EXISTS idx_sources_type ON sources(type);
CREATE INDEX IF NOT EXISTS idx_sources_created_at ON sources(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notebooks_user_id ON notebooks(user_id);
CREATE INDEX IF NOT EXISTS idx_source_tags_source_id ON source_tags(source_id);
CREATE INDEX IF NOT EXISTS idx_source_tags_tag_id ON source_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_tags_user_id ON tags(user_id);
CREATE INDEX IF NOT EXISTS idx_shares_token ON shares(token);
CREATE INDEX IF NOT EXISTS idx_shares_notebook_id ON shares(notebook_id);

-- Media query optimization
CREATE INDEX IF NOT EXISTS idx_sources_media_not_null ON sources(id) WHERE media_data IS NOT NULL;

-- ============================================
-- SETUP COMPLETE
-- ============================================

-- Add comments
COMMENT ON FUNCTION get_user_stats IS 'Get comprehensive statistics for a user';
COMMENT ON FUNCTION search_sources IS 'Full-text search across all user sources';
COMMENT ON FUNCTION get_or_create_tag IS 'Get existing tag or create new one';
COMMENT ON FUNCTION bulk_delete_sources IS 'Delete multiple sources in one operation';
COMMENT ON FUNCTION get_user_media_size IS 'Calculate total media storage used by user';

-- Success message
DO $$
BEGIN
  RAISE NOTICE 'Neon database setup complete! All tables, functions, triggers, and indexes created successfully.';
END $$;
