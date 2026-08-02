-- Code Reviews Migration
-- Adds tables for storing code review history

-- Code reviews table
CREATE TABLE IF NOT EXISTS code_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  code TEXT NOT NULL,
  language VARCHAR(50) NOT NULL,
  review_type VARCHAR(50) NOT NULL DEFAULT 'comprehensive',
  score INTEGER NOT NULL CHECK (score >= 0 AND score <= 100),
  summary TEXT,
  issues JSONB NOT NULL DEFAULT '[]',
  suggestions JSONB NOT NULL DEFAULT '[]',
  context TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_code_reviews_user_id ON code_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_code_reviews_language ON code_reviews(language);
CREATE INDEX IF NOT EXISTS idx_code_reviews_score ON code_reviews(score);
CREATE INDEX IF NOT EXISTS idx_code_reviews_created_at ON code_reviews(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_code_reviews_review_type ON code_reviews(review_type);

-- Code review comparisons table (for tracking improvements)
CREATE TABLE IF NOT EXISTS code_review_comparisons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  original_review_id UUID REFERENCES code_reviews(id) ON DELETE SET NULL,
  updated_review_id UUID REFERENCES code_reviews(id) ON DELETE SET NULL,
  original_code TEXT NOT NULL,
  updated_code TEXT NOT NULL,
  language VARCHAR(50) NOT NULL,
  original_score INTEGER NOT NULL,
  updated_score INTEGER NOT NULL,
  improvement INTEGER NOT NULL,
  resolved_issues JSONB DEFAULT '[]',
  new_issues JSONB DEFAULT '[]',
  summary TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_code_review_comparisons_user_id ON code_review_comparisons(user_id);

-- Update trigger for code_reviews
CREATE OR REPLACE FUNCTION update_code_reviews_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_code_reviews_updated_at ON code_reviews;
CREATE TRIGGER trigger_code_reviews_updated_at
  BEFORE UPDATE ON code_reviews
  FOR EACH ROW
  EXECUTE FUNCTION update_code_reviews_updated_at();
