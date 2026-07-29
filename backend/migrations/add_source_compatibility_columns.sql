-- Keep legacy/fresh core source tables compatible with current notebook,
-- MCP, media, GitHub, and code-review readers.
ALTER TABLE sources
    ADD COLUMN IF NOT EXISTS user_id TEXT,
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS mime_type TEXT,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS summary TEXT,
    ADD COLUMN IF NOT EXISTS media_url TEXT,
    ADD COLUMN IF NOT EXISTS media_path TEXT,
    ADD COLUMN IF NOT EXISTS media_size BIGINT,
    ADD COLUMN IF NOT EXISTS code_analysis JSONB,
    ADD COLUMN IF NOT EXISTS analysis_summary TEXT,
    ADD COLUMN IF NOT EXISTS analysis_rating SMALLINT,
    ADD COLUMN IF NOT EXISTS analyzed_at TIMESTAMPTZ;

DO $$
DECLARE
    source_user_id_type TEXT;
BEGIN
    SELECT data_type
    INTO source_user_id_type
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'sources'
      AND column_name = 'user_id';

    IF source_user_id_type = 'uuid' THEN
        UPDATE sources s
        SET user_id = n.user_id
        FROM notebooks n
        WHERE s.notebook_id = n.id
          AND s.user_id IS NULL;
    ELSE
        UPDATE sources s
        SET user_id = n.user_id::text
        FROM notebooks n
        WHERE s.notebook_id = n.id
          AND s.user_id IS NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sources_user_id ON sources(user_id);
CREATE INDEX IF NOT EXISTS idx_sources_type ON sources(type);
CREATE INDEX IF NOT EXISTS idx_sources_mime_type ON sources(mime_type);
