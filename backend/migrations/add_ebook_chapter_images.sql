ALTER TABLE ebook_chapters
ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]'::jsonb;

UPDATE ebook_chapters
SET images = '[]'::jsonb
WHERE images IS NULL;
