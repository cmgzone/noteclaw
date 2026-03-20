-- Migration: Add typed design artifacts for Planning Mode
-- Establishes a structured design layer alongside freeform design notes.

CREATE TABLE IF NOT EXISTS plan_design_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  artifact_type VARCHAR(30) NOT NULL
    CHECK (artifact_type IN ('prototype', 'design_system', 'screen_set', 'component_library', 'flow')),
  status VARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ready', 'archived')),
  source VARCHAR(30) NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'ai_generated', 'imported')),
  schema_version INTEGER NOT NULL DEFAULT 1,
  root_data JSONB NOT NULL DEFAULT '{}',
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS plan_design_artifact_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artifact_id UUID NOT NULL REFERENCES plan_design_artifacts(id) ON DELETE CASCADE,
  version_number INTEGER NOT NULL,
  snapshot JSONB NOT NULL DEFAULT '{}',
  change_summary TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (artifact_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_plan_id
  ON plan_design_artifacts(plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_type
  ON plan_design_artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_plan_design_artifacts_updated_at
  ON plan_design_artifacts(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_plan_design_artifact_versions_artifact_id
  ON plan_design_artifact_versions(artifact_id);
CREATE INDEX IF NOT EXISTS idx_plan_design_artifact_versions_version
  ON plan_design_artifact_versions(artifact_id, version_number DESC);

CREATE OR REPLACE FUNCTION update_planning_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_plan_design_artifacts_updated_at ON plan_design_artifacts;
CREATE TRIGGER trigger_plan_design_artifacts_updated_at
  BEFORE UPDATE ON plan_design_artifacts
  FOR EACH ROW
  EXECUTE FUNCTION update_planning_updated_at();
