-- Ebook Social Sharing Migration
-- Adds visibility and engagement columns to ebook_projects
-- and updates the shared view counter function to support ebooks.

ALTER TABLE ebook_projects
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS share_count INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_ebook_projects_is_public
  ON ebook_projects(is_public)
  WHERE is_public = true;

CREATE INDEX IF NOT EXISTS idx_ebook_projects_share_count
  ON ebook_projects(share_count DESC);

CREATE OR REPLACE FUNCTION increment_view_count(
    p_content_type VARCHAR(50),
    p_content_id UUID,
    p_viewer_id UUID DEFAULT NULL,
    p_viewer_ip VARCHAR(45) DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_already_viewed BOOLEAN := false;
BEGIN
    IF p_viewer_id IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1
            FROM content_views
            WHERE content_type = p_content_type
              AND content_id = p_content_id
              AND viewer_id = p_viewer_id
        ) INTO v_already_viewed;
    END IF;

    IF NOT v_already_viewed THEN
        INSERT INTO content_views (content_type, content_id, viewer_id, viewer_ip)
        VALUES (p_content_type, p_content_id, p_viewer_id, p_viewer_ip)
        ON CONFLICT DO NOTHING;

        IF p_content_type = 'notebook' THEN
            UPDATE notebooks SET view_count = view_count + 1 WHERE id = p_content_id;
        ELSIF p_content_type = 'plan' THEN
            UPDATE plans SET view_count = view_count + 1 WHERE id = p_content_id;
        ELSIF p_content_type = 'ebook' THEN
            UPDATE ebook_projects
            SET view_count = view_count + 1
            WHERE id::text = p_content_id::text;
        ELSIF p_content_type = 'shared_content' THEN
            UPDATE shared_content SET view_count = view_count + 1 WHERE id = p_content_id;
        END IF;

        RETURN true;
    END IF;

    RETURN false;
END;
$$ LANGUAGE plpgsql;
